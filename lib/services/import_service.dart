import 'package:drift/drift.dart';

import '../data/db/app_db.dart';
import '../data/repositories/finance_repo.dart';
import '../data/repositories/reminders_repo.dart';
import '../native/native_bridge.dart';

/// Imports native batches in one Drift transaction, idempotent on tx_uid / sms_hash / event_uid.
class ImportService {
  ImportService({
    required this.db,
    required this.bridge,
    required this.finance,
    required this.reminders,
  });

  final AppDb db;
  final NativeBridge bridge;
  final FinanceRepo finance;
  final RemindersRepo reminders;

  static const _bankNames = {'melli': 'بانک ملی ایران', 'blu': 'بلو'};

  Future<int> importPending({int maxBatches = 50}) async {
    var imported = 0;
    for (var round = 0; round < maxBatches; round++) {
      final NativeBatch batch;
      try {
        batch = await bridge.drainInbox(limit: 100);
      } on NativeException catch (e) {
        if (e.code == 'db_unavailable') rethrow;
        break;
      }
      if (batch.contractVersion != NativeBridge.contractVersion) {
        await _logEvent('contract_mismatch_${batch.contractVersion}');
        break;
      }
      if (batch.isEmpty) break;
      final counts = await _apply(batch);
      imported += counts;
      await bridge.ackInbox(batch.batchId);
      final progressed = batch.transactions.isNotEmpty ||
          batch.resolutions.isNotEmpty ||
          batch.outcomes.isNotEmpty ||
          batch.occurrences.isNotEmpty;
      if (!progressed) break;
    }
    return imported;
  }

  Future<int> _apply(NativeBatch batch) async {
    var changes = 0;
    await db.transaction(() async {
      for (final sms in batch.sms) {
        final existing = await (db.select(db.rawSms)..where((t) => t.hash.equals(sms.hash))).getSingleOrNull();
        if (existing != null) {
          if (existing.parseStatus == 'received' && sms.parseStatus != 'received') {
            await (db.update(db.rawSms)..where((t) => t.id.equals(existing.id))).write(
              RawSmsCompanion(
                parseStatus: Value(sms.parseStatus),
                templateId: Value(sms.templateId),
                bankCode: Value(sms.bankCode),
                parseErrorCode: Value(sms.errorCode),
                body: Value(sms.body),
              ),
            );
            changes++;
          }
          continue;
        }
        await db.into(db.rawSms).insert(
              RawSmsCompanion.insert(
                sender: sms.sender,
                body: sms.body,
                receivedAt: sms.receivedAt,
                parseStatus: sms.parseStatus,
                templateId: Value(sms.templateId),
                parseErrorCode: Value(sms.errorCode),
                bankCode: Value(sms.bankCode),
                hash: sms.hash,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        changes++;
      }

      final sorted = [...batch.transactions]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      for (final tx in sorted) {
        final account = await _ensureAccount(tx.bankCode, tx.accountHint);
        final raw = await (db.select(db.rawSms)..where((t) => t.hash.equals(tx.smsHash))).getSingleOrNull();
        final existing = await (db.select(db.transactions)..where((t) => t.txUid.equals(tx.txUid)))
            .getSingleOrNull();
        if (existing != null) {
          await _logEvent(tx.txUid);
          continue;
        }
        final previous = await _previousTx(account.id, tx.occurredAt);
        final gap = _gap(previous?.balanceAfterRial, tx.balanceAfterRial, tx.amountRial, tx.direction);
        final inserted = await db.into(db.transactions).insert(
              TransactionsCompanion.insert(
                txUid: tx.txUid,
                accountId: account.id,
                rawSmsId: Value(raw?.id),
                amountRial: tx.amountRial,
                direction: tx.direction,
                occurredAt: tx.occurredAt,
                timeSource: Value(tx.timeSource),
                counterparty: Value(tx.counterparty),
                counterpartySource: Value(tx.counterpartySource),
                purposeText: Value(tx.purposeText),
                label: Value(tx.label),
                smsHash: Value(tx.smsHash),
                balanceAfterRial: Value(tx.balanceAfterRial),
                balanceGapRial: Value(gap),
                createdAt: DateTime.now().toUtc(),
                updatedAt: DateTime.now().toUtc(),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        if (inserted == 0) continue;
        changes++;
        await _logEvent(tx.txUid);
        await _recomputeFollowingGap(account.id, tx.occurredAt);
        await _updateAccountBalance(account, tx.balanceAfterRial, tx.occurredAt);
      }

      for (final resolution in batch.resolutions) {
        final applied = await _applyResolution(resolution);
        if (applied) changes++;
        await _logEvent(resolution.eventUid);
      }

      for (final occurrence in batch.occurrences) {
        await reminders.applyOccurrenceEvent(
          occurrenceUid: occurrence.occurrenceUid,
          reminderId: occurrence.reminderId,
          reason: occurrence.reason,
          scheduledFor: occurrence.scheduledFor,
        );
        await _logEvent(occurrence.eventUid);
        changes++;
      }

      for (final outcome in batch.outcomes) {
        await reminders.applyOutcome(
          occurrenceUid: outcome.occurrenceUid,
          outcome: outcome.outcome,
          resolvedAt: outcome.resolvedAt,
        );
        await _logEvent(outcome.eventUid);
        changes++;
      }
    });
    return changes;
  }

  Future<Account> _ensureAccount(String bankCode, String hint) async {
    final existing = await (db.select(db.accounts)
          ..where((t) => t.bankCode.equals(bankCode) & t.accountHint.equals(hint)))
        .getSingleOrNull();
    if (existing != null) return existing;
    final id = 'acc_${bankCode}_${hint.isEmpty ? 'main' : hint}';
    await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            id: id,
            bankCode: bankCode,
            accountHint: Value(hint),
            displayName: Value(_bankNames[bankCode] ?? bankCode),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return (await (db.select(db.accounts)..where((t) => t.id.equals(id))).getSingle());
  }

  Future<TxRecord?> _previousTx(String accountId, DateTime occurredAt) {
    return (db.select(db.transactions)
          ..where((t) =>
              t.accountId.equals(accountId) &
              t.occurredAt.isSmallerThanValue(occurredAt) &
              t.status.isNotValue('deleted'))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt), (t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  int? _gap(int? previousBalance, int actualBalance, int amount, String direction) {
    if (previousBalance == null) return null;
    final signed = direction == 'in' ? amount : -amount;
    return actualBalance - (previousBalance + signed);
  }

  Future<void> _recomputeFollowingGap(String accountId, DateTime occurredAt) async {
    final next = await (db.select(db.transactions)
          ..where((t) =>
              t.accountId.equals(accountId) &
              t.occurredAt.isBiggerThanValue(occurredAt) &
              t.status.isNotValue('deleted'))
          ..orderBy([(t) => OrderingTerm.asc(t.occurredAt), (t) => OrderingTerm.asc(t.id)])
          ..limit(1))
        .getSingleOrNull();
    if (next == null || next.balanceAfterRial == null) return;
    final self = await (db.select(db.transactions)
          ..where((t) => t.accountId.equals(accountId) & t.occurredAt.equals(occurredAt))
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .getSingleOrNull();
    if (self?.balanceAfterRial == null) return;
    final gap = _gap(self!.balanceAfterRial, next.balanceAfterRial!, next.amountRial, next.direction);
    await (db.update(db.transactions)..where((t) => t.id.equals(next.id))).write(
      TransactionsCompanion(balanceGapRial: Value(gap)),
    );
  }

  Future<void> _updateAccountBalance(Account account, int balance, DateTime occurredAt) async {
    if (account.lastBalanceAt != null && account.lastBalanceAt!.isAfter(occurredAt)) return;
    await (db.update(db.accounts)..where((t) => t.id.equals(account.id))).write(
      AccountsCompanion(
        lastBalanceRial: Value(balance),
        lastBalanceAt: Value(occurredAt),
      ),
    );
  }

  Future<bool> _applyResolution(NativeResolution resolution) async {
    final tx = await (db.select(db.transactions)..where((t) => t.txUid.equals(resolution.txUid)))
        .getSingleOrNull();
    if (tx == null) return false;
    if (resolution.action == 'categorize' && resolution.categoryId != null) {
      await finance.categorize(
        txUid: tx.txUid,
        categoryId: resolution.categoryId!,
        note: resolution.note,
        memoryKey: memoryKeyFor(tx),
      );
      return true;
    }
    if (resolution.note != null && resolution.note!.trim().isNotEmpty) {
      await (db.update(db.transactions)..where((t) => t.id.equals(tx.id))).write(
        TransactionsCompanion(note: Value(resolution.note), updatedAt: Value(DateTime.now().toUtc())),
      );
      return true;
    }
    return false;
  }

  Future<void> _logEvent(String eventUid) async {
    await db.into(db.importLog).insert(
          ImportLogCompanion.insert(eventUid: eventUid, importedAt: DateTime.now().toUtc()),
          mode: InsertMode.insertOrIgnore,
        );
  }

  static String memoryKeyFor(TxRecord tx) {
    final counterparty = tx.counterparty?.trim();
    if (counterparty != null && counterparty.isNotEmpty) return counterparty;
    final purpose = tx.purposeText?.trim();
    if (purpose != null && purpose.isNotEmpty) return purpose;
    return tx.label;
  }

}
