import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_db.dart';

class ReminderWithOccurrence {
  ReminderWithOccurrence({required this.reminder, this.occurrence});
  final Reminder reminder;
  final Occurrence? occurrence;
}

class RemindersRepo {
  RemindersRepo(this.db);

  final AppDb db;
  static const _uuid = Uuid();

  Stream<List<ReminderWithOccurrence>> watchActive() {
    final query = db.select(db.reminders).join([
      leftOuterJoin(
        db.reminderOccurrences,
        db.reminderOccurrences.reminderId.equalsExp(db.reminders.id) &
            db.reminderOccurrences.outcome.equals('pending'),
      ),
    ])
      ..where(db.reminders.status.equals('active'))
      ..orderBy([
        OrderingTerm(expression: db.reminderOccurrences.scheduledFor),
        OrderingTerm(expression: db.reminders.dueAt),
      ]);
    return query.watch().map((rows) => rows
        .map((row) => ReminderWithOccurrence(
              reminder: row.readTable(db.reminders),
              occurrence: row.readTableOrNull(db.reminderOccurrences),
            ))
        .toList());
  }

  Future<Reminder?> byId(String id) =>
      (db.select(db.reminders)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<Occurrence>> occurrences(String reminderId) =>
      (db.select(db.reminderOccurrences)
            ..where((t) => t.reminderId.equals(reminderId))
            ..orderBy([(t) => OrderingTerm(expression: t.scheduledFor)]))
          .get();

  Future<Occurrence?> pendingOccurrence(String reminderId) =>
      (db.select(db.reminderOccurrences)
            ..where((t) => t.reminderId.equals(reminderId) & t.outcome.equals('pending'))
            ..orderBy([(t) => OrderingTerm(expression: t.scheduledFor)])
            ..limit(1))
          .getSingleOrNull();

  Future<Reminder> createReminder({
    required String title,
    String? notes,
    required DateTime dueAt,
    required int priority,
    required int followupCount,
    required int followupIntervalMin,
  }) async {
    final now = DateTime.now().toUtc();
    final reminder = RemindersCompanion.insert(
      id: _uuid.v4(),
      title: title,
      notes: Value(notes),
      dueAt: dueAt,
      priority: Value(priority),
      followupCount: Value(followupCount.clamp(0, 2)),
      followupIntervalMin: Value(followupIntervalMin.clamp(1, 240)),
      rev: const Value(1),
      createdAt: now,
      updatedAt: now,
    );
    return db.into(db.reminders).insertReturning(reminder);
  }

  Future<void> createOccurrence(String reminderId, DateTime scheduledFor) async {
    await db.into(db.reminderOccurrences).insert(
          ReminderOccurrencesCompanion.insert(
            id: _uuid.v4(),
            reminderId: reminderId,
            scheduledFor: scheduledFor,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> updateReminder({
    required String id,
    required String title,
    String? notes,
    required DateTime dueAt,
    required int priority,
    required int followupCount,
    required int followupIntervalMin,
  }) async {
    final current = await byId(id);
    if (current == null) return;
    await (db.update(db.reminders)..where((t) => t.id.equals(id))).write(
      RemindersCompanion(
        title: Value(title),
        notes: Value(notes),
        dueAt: Value(dueAt),
        priority: Value(priority),
        followupCount: Value(followupCount.clamp(0, 2)),
        followupIntervalMin: Value(followupIntervalMin.clamp(1, 240)),
        rev: Value(current.rev + 1),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    final occurrence = await pendingOccurrence(id);
    if (occurrence != null) {
      await (db.update(db.reminderOccurrences)..where((t) => t.id.equals(occurrence.id))).write(
        ReminderOccurrencesCompanion(scheduledFor: Value(dueAt)),
      );
    } else {
      await createOccurrence(id, dueAt);
    }
  }

  Future<void> complete(String id) async {
    await db.transaction(() async {
      await (db.update(db.reminders)..where((t) => t.id.equals(id))).write(
        RemindersCompanion(status: const Value('done'), updatedAt: Value(DateTime.now().toUtc())),
      );
      await (db.update(db.reminderOccurrences)
            ..where((t) => t.reminderId.equals(id) & t.outcome.equals('pending')))
          .write(
        ReminderOccurrencesCompanion(
          outcome: const Value('done'),
          resolvedAt: Value(DateTime.now().toUtc()),
        ),
      );
    });
  }

  Future<void> softDelete(String id) async {
    await (db.update(db.reminders)..where((t) => t.id.equals(id))).write(
      RemindersCompanion(status: const Value('deleted'), updatedAt: Value(DateTime.now().toUtc())),
    );
  }

  Future<List<Occurrence>> pendingOccurrences() =>
      (db.select(db.reminderOccurrences)..where((t) => t.outcome.equals('pending'))).get();

  Future<void> applyOutcome({
    required String occurrenceUid,
    required String outcome,
    DateTime? resolvedAt,
  }) async {
    final occurrence = await (db.select(db.reminderOccurrences)..where((t) => t.id.equals(occurrenceUid)))
        .getSingleOrNull();
    if (occurrence == null) return;
    await (db.update(db.reminderOccurrences)..where((t) => t.id.equals(occurrenceUid))).write(
      ReminderOccurrencesCompanion(
        outcome: Value(outcome),
        resolvedAt: Value(resolvedAt ?? DateTime.now().toUtc()),
      ),
    );
    if (outcome == 'done') {
      await (db.update(db.reminders)..where((t) => t.id.equals(occurrence.reminderId))).write(
        RemindersCompanion(status: const Value('done'), updatedAt: Value(DateTime.now().toUtc())),
      );
    }
  }

  Future<void> applyOccurrenceEvent({
    required String occurrenceUid,
    required String reminderId,
    required String reason,
    required DateTime scheduledFor,
  }) async {
    final reminder = await byId(reminderId);
    if (reminder == null || reminder.status != 'active') return;
    final existing = await (db.select(db.reminderOccurrences)..where((t) => t.id.equals(occurrenceUid)))
        .getSingleOrNull();
    if (existing == null) {
      await db.into(db.reminderOccurrences).insert(
            ReminderOccurrencesCompanion.insert(
              id: occurrenceUid,
              reminderId: reminderId,
              scheduledFor: scheduledFor,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } else {
      await (db.update(db.reminderOccurrences)..where((t) => t.id.equals(occurrenceUid))).write(
        ReminderOccurrencesCompanion(
          scheduledFor: Value(scheduledFor),
          outcome: reason == 'snoozed' ? const Value('pending') : Value(existing.outcome),
          snoozeCount: reason == 'snoozed' ? Value(existing.snoozeCount + 1) : Value(existing.snoozeCount),
        ),
      );
    }
    if (reason == 'rolled_over') {
      await (db.update(db.reminders)..where((t) => t.id.equals(reminderId))).write(
        RemindersCompanion(
          rolloverCount: Value(reminder.rolloverCount + 1),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    }
  }
}
