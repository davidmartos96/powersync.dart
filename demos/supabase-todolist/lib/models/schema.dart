import 'package:powersync/powersync.dart';
import 'package:powersync/attachments/attachments.dart';

const todosTable = 'todos';

const todosCols = [
  Column.text('id'),
  Column.text('list_id'),
  Column.text('photo_id'),
  Column.text('created_at'),
  Column.text('completed_at'),
  Column.text('description'),
  Column.integer('completed'),
  Column.text('created_by'),
  Column.text('completed_by'),
];

const listCols = [
  Column.text('id'),
  Column.text('created_at'),
  Column.text('name'),
  Column.text('owner_id')
];

Schema schema = Schema([
  // const Table(todosTable, [
  //   Column.text('list_id'),
  //   Column.text('photo_id'),
  //   Column.text('created_at'),
  //   Column.text('completed_at'),
  //   Column.text('description'),
  //   Column.integer('completed'),
  //   Column.text('created_by'),
  //   Column.text('completed_by'),
  // ], indexes: [
  //   // Index to allow efficient lookup within a list
  //   Index('list', [IndexedColumn('list_id')])
  // ]),
  // const Table('lists', [
  //   Column.text('created_at'),
  //   Column.text('name'),
  //   Column.text('owner_id')
  // ]),
  // AttachmentsQueueTable()
], rawTables: [
  createRawTableSchemaDefinition(
    listCols,
    "lists",
  ),
  createRawTableSchemaDefinition(
    todosCols,
    todosTable,
  ),
]);

RawTable createRawTableSchemaDefinition(
    List<Column> columns, String tableName) {
  final cols = columns.map((col) => col.name).toList();
  final putSql =
      "INSERT OR REPLACE INTO $tableName (${cols.join(', ')}) VALUES (${cols.map((c) => '?').join(', ')});";
  print("Put sql is $putSql");
  return RawTable(
    name: tableName,
    put: PendingStatement(
      // We need to use INSERT OR REPLACE when defining raw tables
      // ignore: skilldevs_lints/skilldevs_avoid_insert_or_replace_sql
      sql: putSql,
      params: cols
          .map(
            (col) => col == "id"
                ? const PendingStatementValue.id()
                : PendingStatementValue.column(col),
          )
          .toList(),
    ),
    delete: PendingStatement(
      sql: "DELETE FROM $tableName WHERE id = ?",
      params: [const PendingStatementValue.id()],
    ),
  );
}
