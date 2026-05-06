import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart';

Future<void> createRawTableTriggers(
  SqliteWriteContext db,
  String tableName, {
  required List<String> idCols,
  required List<String> tableCols,
}) async {
  // print("Creating table ${info.actualTableName}");

  // we want the op data in the puts ops to include the original id col we used (d_id, b_id, etc) because the server uses them
  await _createRawTableInsertTrigger(db, tableName,
      tableCols: tableCols,
      idCols: idCols.where((col) => col == 'id').toList());
  await _createRawTableUpdateTrigger(db, tableName,
      idCols: idCols, tableCols: tableCols);
  await _createRawTableDeleteTrigger(db, tableName);
}

Future<void> _createRawTableInsertTrigger(
  SqliteWriteContext db,
  String table, {
  required List<String> idCols,
  required List<String> tableCols,
}) async {
  final columns = removeColumns(tableCols, idCols).toList();
  final dataJsonExpr = _buildJsonObjectExpression(
    columns: columns,
    columnPrefix: 'NEW',
  );

  await db.execute('''
CREATE TRIGGER IF NOT EXISTS ${table}_insert
AFTER INSERT ON $table
FOR EACH ROW
BEGIN
  INSERT INTO powersync_crud (op, id, type, data) VALUES('PUT', NEW.id, '$table', $dataJsonExpr);
END;
''');
}

List<String> removeColumns(List<String> tableCols, List<String> colsToRemove) {
  final colsNamesToClean = colsToRemove.toList();
  final columns =
      tableCols.where((col) => !colsNamesToClean.contains(col)).toList();

  return columns;
}

Future<void> _createRawTableUpdateTrigger(
  SqliteWriteContext db,
  String table, {
  required List<String> idCols,
  required List<String> tableCols,
}) async {
  final columns = removeColumns(tableCols, idCols).toList();
  final newRowJsonObj = 'json(${_buildJsonObjectExpression(
    columns: columns,
    columnPrefix: 'NEW',
  )})';

  final oldRowJsonObj = 'json(${_buildJsonObjectExpression(
    columns: columns,
    columnPrefix: 'OLD',
  )})';

  await db.execute('''
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

Future<void> _createRawTableDeleteTrigger(
    SqliteWriteContext db, String table) async {
  await db.execute('''
CREATE TRIGGER ${table}_delete
AFTER DELETE ON $table
FOR EACH ROW
BEGIN
  INSERT INTO powersync_crud (op, type, id) VALUES('DELETE', '$table', OLD.id);
END
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
