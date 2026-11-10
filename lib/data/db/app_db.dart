import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_db.g.dart';

@DriftDatabase(
  tables: [
    Categories,
    Accounts,
    RawSms,
    Transactions,
    MerchantMemory,
    Reminders,
    ReminderOccurrences,
    Settings,
    ImportLog,
  ],
)
class AppDb extends _$AppDb {
  AppDb(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          if (details.wasCreated) {
            await customStatement('PRAGMA journal_mode = WAL');
          }
        },
      );
}
