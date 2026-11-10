import 'package:uuid/uuid.dart';

import '../data/db/app_db.dart';
import '../data/repositories/reminders_repo.dart';
import '../native/native_bridge.dart';

class ReminderService {
  ReminderService({required this.db, required this.repo, required this.bridge});

  final AppDb db;
  final RemindersRepo repo;
  final NativeBridge bridge;
  static const _uuid = Uuid();

  Future<Reminder> create({
    required String title,
    String? notes,
    required DateTime dueAt,
    required int priority,
    required int followupCount,
    required int followupIntervalMin,
  }) async {
    final reminder = await repo.createReminder(
      title: title,
      notes: notes,
      dueAt: dueAt,
      priority: priority,
      followupCount: followupCount,
      followupIntervalMin: followupIntervalMin,
    );
    await repo.createOccurrence(reminder.id, dueAt);
    await syncPending();
    return reminder;
  }

  Future<void> update({
    required String id,
    required String title,
    String? notes,
    required DateTime dueAt,
    required int priority,
    required int followupCount,
    required int followupIntervalMin,
  }) async {
    final before = await repo.pendingOccurrence(id);
    await repo.updateReminder(
      id: id,
      title: title,
      notes: notes,
      dueAt: dueAt,
      priority: priority,
      followupCount: followupCount,
      followupIntervalMin: followupIntervalMin,
    );
    if (before != null) {
      await bridge.cancelAlarm(before.id);
    }
    await syncPending();
  }

  Future<void> complete(String id) async {
    final occurrence = await repo.pendingOccurrence(id);
    await repo.complete(id);
    if (occurrence != null) {
      await bridge.cancelAlarm(occurrence.id);
    }
  }

  Future<void> delete(String id) async {
    final occurrence = await repo.pendingOccurrence(id);
    await repo.softDelete(id);
    if (occurrence != null) {
      await bridge.cancelAlarm(occurrence.id);
    }
  }

  Future<void> syncPending() async {
    final occurrences = await repo.pendingOccurrences();
    for (final occurrence in occurrences) {
      final reminder = await repo.byId(occurrence.reminderId);
      if (reminder == null || reminder.status != 'active') continue;
      await bridge.upsertAlarm({
        'occurrenceUid': occurrence.id,
        'reminderId': reminder.id,
        'rev': reminder.rev,
        'title': reminder.title,
        'scheduledFor': occurrence.scheduledFor.millisecondsSinceEpoch,
        'followupCount': reminder.followupCount,
        'followupIntervalMin': reminder.followupIntervalMin,
        'priority': reminder.priority,
      });
    }
  }

  Future<void> addQuick({required String title, required DateTime dueAt}) async {
    await create(
      title: title,
      dueAt: dueAt,
      priority: 1,
      followupCount: 2,
      followupIntervalMin: 15,
    );
  }

  static String newId() => _uuid.v4();
}
