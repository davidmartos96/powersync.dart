import 'package:powersync/powersync.dart';
import 'package:powersync_flutter_demo/models/schema.dart';
import 'package:sqlite_async/sqlite_async.dart';

// A table to hold a custom schema version number
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

    print("Migrating from custom db schema version $schemaVersion to $latestSchemaVersion");
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
  // Triggers
  await _createInsertListTriggers(ctx);
  await _createUpdateListTrigger(ctx);
  await _createDeleteListTrigger(ctx);
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

Future<void> _createInsertListTriggers(SqliteWriteContext ctx) async {
  final table = listsRawTable;
  final dataJsonExpr = 'json(${_buildJsonObjectExpression(
    columns: [
      'created_at',
      'name',
      'owner_id',
    ],
    columnPrefix: 'NEW',
  )})';

  await ctx.execute('''
CREATE TRIGGER IF NOT EXISTS ${table}_insert
AFTER INSERT ON $table
FOR EACH ROW
WHEN NOT powersync_in_sync_operation()
BEGIN
  INSERT INTO powersync_crud_(data) VALUES(json_object('op', 'PUT', 'type', '$table', 'id', NEW.id, 'data', $dataJsonExpr));
  INSERT OR IGNORE INTO ps_updated_rows(row_type, row_id) VALUES('$table', NEW.id);
  INSERT OR REPLACE INTO ps_buckets(name, last_op, target_op) VALUES('\$local', 0, 9223372036854775807);
END;
''');
}

String _buildJsonObjectExpression(
    {required List<String> columns, String? columnPrefix}) {
  final list = columns.map((columnName) {
    final String key = "'$columnName'";
    final String value =
        columnPrefix != null ? '$columnPrefix.$columnName' : columnName;
    return '$key, $value';
  }).join(', ');

  return "json_object($list)";
}

Future<void> _createUpdateListTrigger(SqliteWriteContext ctx) async {
  final table = listsRawTable;
  final columns = [
    'created_at',
    'name',
    'owner_id',
  ];
  final newRowJsonObj = 'json(${_buildJsonObjectExpression(
    columns: columns,
    columnPrefix: 'NEW',
  )})';

  final oldRowJsonObj = 'json(${_buildJsonObjectExpression(
    columns: columns,
    columnPrefix: 'OLD',
  )})';

  await ctx.execute('''
CREATE TRIGGER ${table}_update
AFTER UPDATE ON $table
FOR EACH ROW
BEGIN
  SELECT CASE
  WHEN (OLD.id != NEW.id)
  THEN RAISE (FAIL, 'Cannot update id')
  END;
  INSERT INTO powersync_crud_(data, options)
  VALUES(json_object('op', 'PATCH', 'type', '$table', 'id', NEW.id, 'data', json(powersync_diff($oldRowJsonObj, $newRowJsonObj))), 0);
  INSERT OR IGNORE INTO ps_updated_rows(row_type, row_id) VALUES('$table', NEW.id);
  INSERT OR REPLACE INTO ps_buckets(name, last_op, target_op) VALUES('\$local', 0, 9223372036854775807);
END
''');
}

Future<void> _createDeleteListTrigger(SqliteWriteContext ctx) async {
  final table = listsRawTable;
  await ctx.execute('''
CREATE TRIGGER ${table}_delete
AFTER DELETE ON $table
FOR EACH ROW
BEGIN
  INSERT INTO powersync_crud_(data) VALUES(json_object('op', 'DELETE', 'type', '$table', 'id', OLD.id));
  INSERT OR IGNORE INTO ps_updated_rows(row_type, row_id) VALUES('$table', OLD.id);
  INSERT OR REPLACE INTO ps_buckets(name, last_op, target_op) VALUES('\$local', 0, 9223372036854775807);
END
''');
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
