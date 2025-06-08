import 'package:powersync/powersync.dart';
import 'package:powersync_flutter_demo/models/schema.dart';
import 'package:sqlite_async/sqlite_async.dart';

Future<void> initializeRawTablesSchema(PowerSyncDatabase db) async {
  await db.writeTransaction((ctx) async {
    await _createListsRawTable(ctx);
  });
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
