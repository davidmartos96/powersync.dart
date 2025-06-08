import 'package:powersync/powersync.dart';
import 'package:powersync_flutter_demo/models/schema.dart';
import 'package:sqlite_async/sqlite_async.dart';

const _versionTable = 'custom_schema_version';
const latestSchemaVersion = 1;

Future<void> initializeRawTablesSchema(PowerSyncDatabase db) async {
  await _setupSchemaVersionTable(db);

  await db.writeTransaction((ctx) async {
    final schemaVersion = await _getSchemaVersion(ctx);

    if (schemaVersion == latestSchemaVersion) {
      return;
    }

    if (schemaVersion > latestSchemaVersion) {
      throw Exception(
          "Database is in a newer version than expected ($schemaVersion)");
    }

    for (var i = schemaVersion; i < latestSchemaVersion; i++) {
      assert(_migrationsMap.containsKey(i),
          'Migrations map is missing migration from version $i');
      await _migrationsMap[i]!(ctx);
    }

    await _setSchemaVersion(ctx, latestSchemaVersion);
  });
}

Map<int, Future<void> Function(SqliteWriteContext)> _migrationsMap = {
  0: _migrateFrom0,
};

Future<void> _migrateFrom0(SqliteWriteContext ctx) async {
  await _createListsRawTable(ctx);
  await insertListTriggers(ctx);
}

Future<void> _createListsRawTable(SqliteWriteContext ctx) async {
  await ctx.execute('''
CREATE TABLE IF NOT EXISTS $listsRawTable(
  id TEXT NOT NULL PRIMARY KEY,
  created_at TEXT NOT NULL,
  name TEXT NOT NULL,
  owner_id TEXT NOT NULL
) STRICT;
''');
}

Future<void> insertListTriggers(SqliteWriteContext ctx) async {
  final table = listsRawTable;
  final dataJsonExpr = "json(json_object('created_at', NEW.created_at, 'name', NEW.name, 'owner_id', NEW.owner_id))";

  final insert = '''
INSERT INTO powersync_crud_(data)
VALUES(json_object('op', 'PUT', 'type', '$table', 'id', NEW.id, 'data', $dataJsonExpr));
''';

  await ctx.execute('''
CREATE TRIGGER IF NOT EXISTS ${table}_insert
AFTER INSERT ON $table
FOR EACH ROW
--WHEN NOT powersync_in_sync_operation()
BEGIN
  $insert
END;
''');

// Default insert trigger from powersync
  /*
  await ctx.execute('''
CREATE TRIGGER fts_insert_trigger_todos AFTER INSERT ON ps_data__todos
      BEGIN
        INSERT INTO powersync_crud_(data) VALUES(json_object('op', 'PUT', 'type', 'todos', 'id', NEW.id, 'data', json(powersync_diff('{}', json_object('list_id', NEW."list_id", 'photo_id', NEW."photo_id", 'created_at', NEW."created_at", 'completed_at', NEW."completed_at", 'description', NEW."description", 'completed', NEW."completed", 'created_by', NEW."created_by", 'completed_by', NEW."completed_by")))));
      INSERT OR IGNORE INTO ps_updated_rows(row_type, row_id) VALUES('todos', NEW.id);
      INSERT OR REPLACE INTO ps_buckets(name, last_op, target_op) VALUES('$local', 0, 9223372036854775807);
      END
'''); */
}

Future<void> _setupSchemaVersionTable(PowerSyncDatabase db) async {
  await db.writeTransaction((ctx) async {
    // Create a simple version table to manage migrations.
    await ctx.execute('''
    CREATE TABLE IF NOT EXISTS $_versionTable (
      version INTEGER PRIMARY KEY
    );
  ''');

    // If no version is recorded, insert the initial version.
    final result =
        await ctx.get('SELECT COUNT(*) as count FROM $_versionTable;');
    final count = result['count'] as int;
    if (count == 0) {
      await ctx.execute('INSERT INTO $_versionTable (version) VALUES (0);');
    }
  });
}

Future<int> _getSchemaVersion(SqliteReadContext db) async {
  final result = await db.get('SELECT version FROM $_versionTable;');
  return result['version'] as int;
}

Future<void> _setSchemaVersion(SqliteWriteContext db, int version) async {
  await db.execute('UPDATE $_versionTable SET version = ?;', [version]);
}
