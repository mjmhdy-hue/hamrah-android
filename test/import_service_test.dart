import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hamrah/data/db/app_db.dart';
import 'package:hamrah/data/db/seed.dart';
import 'package:hamrah/data/repositories/finance_repo.dart';
import 'package:hamrah/data/repositories/reminders_repo.dart';
import 'package:hamrah/native/native_bridge.dart';
import 'package:hamrah/services/import_service.dart';

/// Fixture expectations from Appendix A: amount, balance, direction, occurredAt (UTC).
const _fixtures = <String, List<Object>>{
  'M1': ['melli', '55555', 'out', 300000, 2404048, '2026-10-31T17:45:00Z', 'برداشت'],
  'M2': ['melli', '55555', 'out', 1000000, 1404048, '2026-10-31T17:59:00Z', 'برداشت'],
  'M3': ['melli', '55555', 'out', 1333500, 70548, '2026-11-07T11:46:00Z', 'خرید اینترنتی'],
  'M4': ['melli', '55555', 'in', 410764899, 410786048, '2026-10-31T07:34:00Z', 'حقوق'],
  'M5': ['melli', '55555', 'out', 410000000, 786048, '2026-10-31T07:38:00Z', 'حواله پل'],
  'M6': ['melli', '55555', 'in', 2000000, 2704048, '2026-10-31T17:44:00Z', 'حواله پل'],
  'B1': ['blu', '', 'out', 2600000, 50038727, '2026-11-06T08:35:00Z', 'برداشت پول'],
  'B2': ['blu', '', 'out', 18000000, 32038727, '2026-11-06T09:02:00Z', 'برداشت پول'],
  'B3': ['blu', '', 'out', 900000, 84085, '2026-10-23T13:03:00Z', 'برداشت پول'],
  'B4': ['blu', '', 'in', 200000, 284085, '2026-10-23T15:02:00Z', 'واریز پول'],
  'B5': ['blu', '', 'out', 245300, 38785, '2026-10-23T15:03:00Z', 'خرید بسته اینترنت'],
  'B6': ['blu', '', 'in', 10000000, 10038785, '2026-10-26T16:44:00Z', 'واریز پول'],
  'B8': ['blu', '', 'out', 468710, 9570075, '2026-10-26T19:19:00Z', 'برداشت پول'],
  'B9': ['blu', '', 'out', 245300, 2112437, '2026-11-09T14:53:00Z', 'خرید بسته اینترنت'],
  'B10': ['blu', '', 'out', 245300, 1867137, '2026-11-09T20:07:00Z', 'خرید بسته اینترنت'],
};

class FakeBridge extends NativeBridge {
  FakeBridge(this.batches);
  final List<Map<String, dynamic>> batches;
  final acked = <String>[];
  int idx = 0;

  @override
  Future<NativeBatch> drainInbox({int limit = 100}) async {
    if (idx >= batches.length) {
      return NativeBatch(
        batchId: 'empty',
        contractVersion: NativeBridge.contractVersion,
        sms: const [], transactions: const [], resolutions: const [],
        outcomes: const [], occurrences: const [],
      );
    }
    return NativeBatch.fromJson(batches[idx++]);
  }

  @override
  Future<void> ackInbox(String batchId) async => acked.add(batchId);

  @override
  Future<void> restoreAlarms() async {}
}

Map<String, dynamic> batchFor(String id) {
  final f = _fixtures[id]!;
  final occurred = DateTime.parse(f[5] as String);
  final hash = 'hash-$id';
  return {
    'batchId': 'batch-$id',
    'contractVersion': 1,
    'sms': [
      {
        'eventUid': 'sms-$id', 'sender': f[0], 'body': 'fixture body $id',
        'receivedAt': occurred.millisecondsSinceEpoch, 'parseStatus': 'parsed',
        'hash': hash, 'templateId': f[0] == 'melli' ? 'melli_v1' : 'blu_debit_v1',
        'bankCode': f[0], 'errorCode': null, 'partCount': 1,
      }
    ],
    'transactions': [
      {
        'txUid': 'tx-$id', 'smsEventUid': 'sms-$id', 'smsHash': hash,
        'bankCode': f[0], 'accountHint': f[1], 'direction': f[2],
        'amountRial': f[3], 'occurredAt': occurred.millisecondsSinceEpoch,
        'timeSource': 'body', 'counterparty': null, 'counterpartySource': null,
        'purposeText': f[0] == 'blu' && (f[6] as String).contains('اینترنت') ? 'خرید بسته اینترنت' : null,
        'label': f[6], 'balanceAfterRial': f[4], 'suggestionKey': f[6],
      }
    ],
    'resolutions': [], 'outcomes': [], 'occurrences': [],
  };
}

void main() {
  late AppDb db;
  late FinanceRepo finance;
  late FakeBridge bridge;
  late ImportService importer;

  setUp(() async {
    db = AppDb(NativeDatabase.memory());
    await seedDatabase(db);
    finance = FinanceRepo(db);
    bridge = FakeBridge([for (final id in _fixtures.keys) batchFor(id)]);
    importer = ImportService(db: db, bridge: bridge, finance: finance, reminders: RemindersRepo(db));
  });

  tearDown(() async => db.close());

  test('imports all parsed fixtures once and acks every batch', () async {
    await importer.importPending();
    final rows = await db.select(db.transactions).get();
    expect(rows.length, 15);
    expect(bridge.acked.length, 15);
    final accounts = await db.select(db.accounts).get();
    expect(accounts.length, 2);
  });

  test('replaying the same batch does not duplicate anything', () async {
    await importer.importPending();
    bridge.idx = 0;
    await importer.importPending();
    final rows = await db.select(db.transactions).get();
    expect(rows.length, 15);
  });

  test('balance gaps: listed pairs are clean, M5 -> M6 is -82000', () async {
    await importer.importPending();
    final rows = await db.select(db.transactions).get();
    final byHash = {for (final r in rows) r.smsHash!: r};
    const pairs = [
      ['M6', 'M1'], ['M1', 'M2'], ['M2', 'M3'], ['M4', 'M5'],
      ['B1', 'B2'], ['B3', 'B4'], ['B4', 'B5'], ['B5', 'B6'], ['B6', 'B8'], ['B9', 'B10'],
    ];
    for (final pair in pairs) {
      expect(byHash['hash-${pair[1]}']!.balanceGapRial, 0,
          reason: '${pair[0]} -> ${pair[1]} should be continuous');
    }
    expect(byHash['hash-M6']!.balanceGapRial, -82000, reason: 'M5 -> M6 known gap');
    // Fixtures are a partial capture: B8 -> B1 spans missing messages and must be reported, not fixed.
    expect(byHash['hash-B1']!.balanceGapRial, isNot(0));
  });

  test('B9 and B10 are two distinct transactions', () async {
    await importer.importPending();
    final rows = await db.select(db.transactions).get();
    final b9 = rows.where((r) => r.smsHash == 'hash-B9').toList();
    final b10 = rows.where((r) => r.smsHash == 'hash-B10').toList();
    expect(b9.length, 1);
    expect(b10.length, 1);
    expect(b9.first.balanceAfterRial, 2112437);
    expect(b10.first.balanceAfterRial, 1867137);
  });

  test('account last balance follows the newest occurred_at', () async {
    await importer.importPending();
    final accounts = await db.select(db.accounts).get();
    final blu = accounts.firstWhere((a) => a.bankCode == 'blu');
    expect(blu.lastBalanceRial, 1867137);
    final melli = accounts.firstWhere((a) => a.bankCode == 'melli');
    expect(melli.lastBalanceRial, 70548);
  });
}
