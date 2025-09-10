import 'package:powersync/powersync.dart';
import 'package:powersync_attachments_helper/powersync_attachments_helper.dart';

const todosTable = 'todos';
const listsRawTable = 'lists';

const manualSchemaMngmtMode = true;

Schema schema = Schema([
  const Table(todosTable, [
    Column.text('list_id'),
    Column.text('photo_id'),
    Column.text('created_at'),
    Column.text('completed_at'),
    Column.text('description'),
    Column.integer('completed'),
    Column.text('created_by'),
    Column.text('completed_by'),
  ], indexes: [
    // Index to allow efficient lookup within a list
    Index('list', [IndexedColumn('list_id')])
  ]),
  if (!manualSchemaMngmtMode)
    const Table('lists', [Column.text('created_at'), Column.text('name'), Column.text('owner_id')]),
  AttachmentsQueueTable(
    attachmentsQueueTableName: defaultAttachmentsQueueTableName,
  ),
], rawTables: [
  if (manualSchemaMngmtMode)
    RawTable(
      name: 'lists',
      put: PendingStatement(
        sql: "INSERT OR REPLACE INTO $listsRawTable (id, created_at, name, owner_id) VALUES (?, ?, ?, ?);",
        params: [
          PendingStatementValue.id(),
          PendingStatementValue.column('created_at'),
          PendingStatementValue.column('name'),
          PendingStatementValue.column('owner_id'),
        ],
      ),
      delete: PendingStatement(
        sql: "DELETE FROM $listsRawTable WHERE id = ?",
        params: [PendingStatementValue.id()],
      ),
    )
]);
