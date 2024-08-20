import 'package:powersync/powersync.dart';
import 'package:powersync/sqlite3.dart' as sqlite;
import 'package:powersync_flutter_demo/database.dart';

import '../powersync.dart';

/// TodoList represents a result row of a query on "lists".
///
/// This class is immutable - methods on this class do not modify the instance
/// directly. Instead, watch or re-query the data to get the updated list.
class TodoList {
  static Stream<SyncStatus> watchSyncStatus() {
    return db.statusStream;
  }
}
