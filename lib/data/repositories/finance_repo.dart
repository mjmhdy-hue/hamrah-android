import 'package:drift/drift.dart';

import '../db/app_db.dart';

class TxRow {
  TxRow({required this.tx, this.category, this.rawSms});
  final TxRecord tx;
  final Category? category;
  final SmsRecord? rawSms;
}

class FinanceRepo {
  FinanceRepo(this.db);

  final AppDb db;

  Stream<List<Account>> watchAccounts() =>
      (db.select(db.accounts)..orderBy([(t) => OrderingTerm(expression: t.bankCode)])).watch();

  Future<List<Account>> accounts() => db.select(db.accounts).get();

  Stream<List<Category>> watchCategories({bool includeTransfer = true}) {
    final query = db.select(db.categories)
      ..where((t) => t.archived.equals(false))
      ..orderBy([(t) => OrderingTerm(expression: t.type), (t) => OrderingTerm(expression: t.nameFa)]);
    if (!includeTransfer) query.where((t) => t.type.isNotValue('transfer'));
    return query.watch();
  }

  Future<List<Category>> categories() => db.select(db.categories).get();

  Stream<List<TxRow>> watchTransactions({int limit = 200, String? search, String? status}) {
    final query = db.select(db.transactions).join([
      leftOuterJoin(db.categories, db.categories.id.equalsExp(db.transactions.categoryId)),
      leftOuterJoin(db.rawSms, db.rawSms.id.equalsExp(db.transactions.rawSmsId)),
    ]);
    query.where(db.transactions.status.isNotValue('deleted'));
    if (status != null) query.where(db.transactions.status.equals(status));
    if (search != null && search.trim().isNotEmpty) {
      final term = '%${search.trim()}%';
      query.where(
        db.transactions.counterparty.like(term) |
            db.transactions.purposeText.like(term) |
            db.transactions.note.like(term) |
            db.transactions.label.like(term),
      );
    }
    query
      ..orderBy([OrderingTerm.desc(db.transactions.occurredAt), OrderingTerm.desc(db.transactions.id)])
      ..limit(limit);
    return query.watch().map((rows) => rows
        .map((row) => TxRow(
              tx: row.readTable(db.transactions),
              category: row.readTableOrNull(db.categories),
              rawSms: row.readTableOrNull(db.rawSms),
            ))
        .toList());
  }

  Stream<int> watchPendingCount() {
    final query = db.selectOnly(db.transactions)
      ..addColumns([db.transactions.id.count()])
      ..where(db.transactions.status.equals('pending_category') & db.transactions.deletedAt.isNull());
    return query.watchSingle().map((row) => row.read(db.transactions.id.count()) ?? 0);
  }

  Stream<int> watchUnrecognizedCount() {
    final query = db.selectOnly(db.rawSms)
      ..addColumns([db.rawSms.id.count()])
      ..where(db.rawSms.parseStatus.equals('unrecognized'));
    return query.watchSingle().map((row) => row.read(db.rawSms.id.count()) ?? 0);
  }

  Future<int> unrecognizedCount() async {
    final query = db.selectOnly(db.rawSms)
      ..addColumns([db.rawSms.id.count()])
      ..where(db.rawSms.parseStatus.equals('unrecognized'));
    final row = await query.getSingle();
    return row.read(db.rawSms.id.count()) ?? 0;
  }

  Stream<List<SmsRecord>> watchUnrecognized() {
    final query = db.select(db.rawSms)
      ..where((t) => t.parseStatus.equals('unrecognized'))
      ..orderBy([(t) => OrderingTerm.desc(t.receivedAt)]);
    return query.watch();
  }

  Stream<List<TxRow>> watchPending() {
    final query = db.select(db.transactions).join([
      leftOuterJoin(db.categories, db.categories.id.equalsExp(db.transactions.categoryId)),
      leftOuterJoin(db.rawSms, db.rawSms.id.equalsExp(db.transactions.rawSmsId)),
    ])
      ..where(db.transactions.status.equals('pending_category') & db.transactions.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(db.transactions.occurredAt)]);
    return query.watch().map((rows) => rows
        .map((row) => TxRow(
              tx: row.readTable(db.transactions),
              category: row.readTableOrNull(db.categories),
              rawSms: row.readTableOrNull(db.rawSms),
            ))
        .toList());
  }

  Future<TxRow?> byUid(String txUid) async {
    final query = db.select(db.transactions).join([
      leftOuterJoin(db.categories, db.categories.id.equalsExp(db.transactions.categoryId)),
      leftOuterJoin(db.rawSms, db.rawSms.id.equalsExp(db.transactions.rawSmsId)),
    ])..where(db.transactions.txUid.equals(txUid));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return TxRow(
      tx: row.readTable(db.transactions),
      category: row.readTableOrNull(db.categories),
      rawSms: row.readTableOrNull(db.rawSms),
    );
  }

  Future<void> categorize({
    required String txUid,
    required String categoryId,
    String? note,
    required String memoryKey,
  }) async {
    await db.transaction(() async {
      final tx = await (db.select(db.transactions)..where((t) => t.txUid.equals(txUid))).getSingleOrNull();
      if (tx == null) return;
      await (db.update(db.transactions)..where((t) => t.id.equals(tx.id))).write(
        TransactionsCompanion(
          categoryId: Value(categoryId),
          note: Value(note ?? tx.note),
          status: const Value('categorized'),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await _rememberMerchant(memoryKey, categoryId);
    });
  }

  Future<void> _rememberMerchant(String key, String categoryId) async {
    if (key.trim().isEmpty) return;
    final existing = await (db.select(db.merchantMemory)..where((t) => t.key.equals(key))).getSingleOrNull();
    if (existing == null) {
      await db.into(db.merchantMemory).insert(
            MerchantMemoryCompanion.insert(
              key: key,
              categoryId: categoryId,
              lastUsedAt: DateTime.now().toUtc(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } else {
      await (db.update(db.merchantMemory)..where((t) => t.key.equals(key))).write(
        MerchantMemoryCompanion(
          categoryId: Value(categoryId),
          useCount: Value(existing.useCount + 1),
          lastUsedAt: Value(DateTime.now().toUtc()),
        ),
      );
    }
  }

  Future<void> softDelete(String txUid) async {
    await (db.update(db.transactions)..where((t) => t.txUid.equals(txUid))).write(
      TransactionsCompanion(
        status: const Value('deleted'),
        deletedAt: Value(DateTime.now().toUtc()),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<Map<String, String>> merchantMemory() async {
    final rows = await db.select(db.merchantMemory).get();
    return {for (final row in rows) row.key: row.categoryId};
  }

  /// Latest non-zero balance gap per account (bank-reported balance mismatch).
  Future<Map<String, int>> latestGaps() async {
    final rows = await (db.select(db.transactions)
          ..where((t) =>
              t.balanceGapRial.isNotNull() &
              t.balanceGapRial.isNotValue(0) &
              t.status.isNotValue('deleted'))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .get();
    final result = <String, int>{};
    for (final row in rows) {
      result.putIfAbsent(row.accountId, () => row.balanceGapRial!);
    }
    return result;
  }

  Future<List<String>> accountIdsWithAnyGap() async => (await latestGaps()).keys.toList();

  Future<Map<String, int>> monthlyTotals(DateTime fromUtc) async {
    final query = db.selectOnly(db.transactions)
      ..addColumns([db.transactions.direction, db.transactions.amountRial.sum()])
      ..where(db.transactions.occurredAt.isBiggerOrEqualValue(fromUtc) &
          db.transactions.deletedAt.isNull() &
          db.transactions.status.isNotValue('deleted'))
      ..groupBy([db.transactions.direction]);
    final rows = await query.get();
    final result = <String, int>{'in': 0, 'out': 0};
    for (final row in rows) {
      final direction = row.read(db.transactions.direction);
      final sum = row.read(db.transactions.amountRial.sum()) ?? 0;
      if (direction != null) result[direction] = sum;
    }
    return result;
  }
}
