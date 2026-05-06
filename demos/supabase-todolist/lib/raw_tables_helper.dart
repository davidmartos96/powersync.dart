import 'package:powersync/powersync.dart';
import 'package:powersync_flutter_demo/models/schema.dart';
import 'package:powersync_flutter_demo/utils.dart';
import 'package:sqlite_async/sqlite_async.dart';

// A table to hold a custom schema version number
const _versionTable = 'custom_schema_version';
const latestSchemaVersion = 1;
const listsRawTable = "lists";

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

    print(
        "Migrating from custom db schema version $schemaVersion to $latestSchemaVersion");
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
  await _createTodosRawTable(ctx);
  await createRawTableTriggers(ctx, "lists",
      idCols: ["id"], tableCols: listCols.map((col) => col.name).toList());
  await createRawTableTriggers(ctx, "todos",
      idCols: ["id"], tableCols: todosCols.map((col) => col.name).toList());
  print("Applied migrations");
}

Future<void> _createListsRawTable(SqliteWriteContext ctx) async {
  await ctx.execute('''
CREATE TABLE IF NOT EXISTS $listsRawTable(
  id TEXT NOT NULL PRIMARY KEY,
  created_at TEXT NOT NULL,
  name TEXT NOT NULL,
  owner_id TEXT NOT NULL
) ;
''');
}

Future<void> _createTodosRawTable(SqliteWriteContext ctx) async {
  await ctx.execute('''
CREATE TABLE IF NOT EXISTS todos(
  id TEXT NOT NULL PRIMARY KEY,
  list_id TEXT NOT NULL,
  photo_id TEXT ,
  created_at TEXT NOT NULL,
  completed_at TEXT ,
  description TEXT NOT NULL,
  completed INTEGER NOT NULL,
  created_by TEXT ,
  completed_by TEXT,
  CONSTRAINT fk_lists FOREIGN KEY (list_id) REFERENCES lists(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
) ;
''');
}

Future<void> _createInsertListTriggers(SqliteWriteContext ctx) async {
  final table = listsRawTable;
  final dataJsonExpr = _buildJsonObjectExpression(
    columns: [
      'created_at',
      'name',
      'owner_id',
    ],
    columnPrefix: 'NEW',
  );

  await ctx.execute('''
CREATE TRIGGER IF NOT EXISTS ${table}_insert
AFTER INSERT ON $table
FOR EACH ROW
BEGIN
  INSERT INTO powersync_crud (op, id, type, data) VALUES('PUT',NEW.id, '$table', $dataJsonExpr);
END;
''');
}

Future<void> _createInsertTodoTriggers(SqliteWriteContext ctx) async {
  final table = listsRawTable;
  final dataJsonExpr = _buildJsonObjectExpression(
    columns: [],
    columnPrefix: 'NEW',
  );

  await ctx.execute('''
CREATE TRIGGER IF NOT EXISTS ${table}_insert
AFTER INSERT ON $table
FOR EACH ROW
BEGIN
  INSERT INTO powersync_crud (op, id, type, data) VALUES('PUT',NEW.id, '$table', $dataJsonExpr);
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
  INSERT INTO powersync_crud (op, id, type, data)
  VALUES('PATCH', NEW.id, '$table', powersync_diff($oldRowJsonObj, $newRowJsonObj));
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
  INSERT INTO powersync_crud (op, type, id) VALUES('DELETE', '$table', OLD.id);
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
