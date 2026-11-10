import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/formatting.dart';
import 'data/db/app_db.dart';
import 'data/repositories/finance_repo.dart';
import 'data/repositories/reminders_repo.dart';
import 'data/repositories/settings_repo.dart';
import 'native/native_bridge.dart';
import 'services/import_service.dart';
import 'services/reminder_service.dart';
import 'services/snapshot_service.dart';
import 'services/voice_service.dart';

final dbProvider = Provider<AppDb>((ref) => throw UnimplementedError('db not initialized'));
final bridgeProvider = Provider<NativeBridge>((ref) => throw UnimplementedError('bridge not initialized'));
final datesProvider = Provider<Dates>((ref) => Dates());

final settingsRepoProvider = Provider<SettingsRepo>((ref) => SettingsRepo(ref.watch(dbProvider)));
final financeRepoProvider = Provider<FinanceRepo>((ref) => FinanceRepo(ref.watch(dbProvider)));
final remindersRepoProvider = Provider<RemindersRepo>((ref) => RemindersRepo(ref.watch(dbProvider)));
final voiceServiceProvider = Provider<VoiceService>((ref) {
  final service = VoiceService();
  ref.onDispose(service.stop);
  return service;
});

final snapshotServiceProvider = Provider<SnapshotService>(
  (ref) => SnapshotService(
    db: ref.watch(dbProvider),
    settings: ref.watch(settingsRepoProvider),
    bridge: ref.watch(bridgeProvider),
  ),
);

final importServiceProvider = Provider<ImportService>(
  (ref) => ImportService(
    db: ref.watch(dbProvider),
    bridge: ref.watch(bridgeProvider),
    finance: ref.watch(financeRepoProvider),
    reminders: ref.watch(remindersRepoProvider),
  ),
);

final reminderServiceProvider = Provider<ReminderService>(
  (ref) => ReminderService(
    db: ref.watch(dbProvider),
    repo: ref.watch(remindersRepoProvider),
    bridge: ref.watch(bridgeProvider),
  ),
);

final settingsStreamProvider = StreamProvider<Map<String, String>>(
  (ref) => ref.watch(settingsRepoProvider).watchAll(),
);

final accountsProvider = StreamProvider((ref) => ref.watch(financeRepoProvider).watchAccounts());
final categoriesProvider = StreamProvider((ref) => ref.watch(financeRepoProvider).watchCategories());
final pendingCountProvider = StreamProvider((ref) => ref.watch(financeRepoProvider).watchPendingCount());
final unrecognizedCountProvider =
    StreamProvider((ref) => ref.watch(financeRepoProvider).watchUnrecognizedCount());
final pendingTransactionsProvider = StreamProvider((ref) => ref.watch(financeRepoProvider).watchPending());
final remindersProvider = StreamProvider((ref) => ref.watch(remindersRepoProvider).watchActive());
final todayTotalsProvider = FutureProvider((ref) async {
  final dates = ref.watch(datesProvider);
  final start = dates.startOfTodayUtc();
  return ref.watch(financeRepoProvider).monthlyTotals(start);
});

/// Coordinates snapshot push + inbox import at start and resume.
class SyncCoordinator {
  SyncCoordinator({
    required this.snapshot,
    required this.importer,
    required this.reminders,
    required this.bridge,
  });

  final SnapshotService snapshot;
  final ImportService importer;
  final ReminderService reminders;
  final NativeBridge bridge;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  bool _running = false;

  Future<void> run({bool force = false}) async {
    if (_running) return;
    if (!force && DateTime.now().difference(_lastRun) < const Duration(seconds: 4)) return;
    _running = true;
    try {
      await snapshot.sync();
      await importer.importPending();
      await reminders.syncPending();
      await bridge.restoreAlarms();
      _lastRun = DateTime.now();
    } catch (_) {
      // diagnosed in the Diagnostics screen; never blocks the UI
    } finally {
      _running = false;
    }
  }
}

final syncCoordinatorProvider = Provider<SyncCoordinator>(
  (ref) => SyncCoordinator(
    snapshot: ref.watch(snapshotServiceProvider),
    importer: ref.watch(importServiceProvider),
    reminders: ref.watch(reminderServiceProvider),
    bridge: ref.watch(bridgeProvider),
  ),
);
