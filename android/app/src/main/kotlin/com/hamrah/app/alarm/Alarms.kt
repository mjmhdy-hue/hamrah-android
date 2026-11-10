package com.hamrah.app.alarm

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.hamrah.app.Contract
import com.hamrah.app.DiagCodes
import com.hamrah.app.MainActivity
import com.hamrah.app.R
import com.hamrah.app.db.NativeInboxDb
import com.hamrah.app.notify.NotificationChannels
import com.hamrah.app.sms.NativeSnapshot
import com.hamrah.app.util.PersianFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

class AlarmScheduler(private val context: Context) {

    companion object {
        const val ACTION_FIRE = "com.hamrah.app.action.ALARM_FIRE"
        const val ACTION_ROLLOVER = "com.hamrah.app.action.ROLLOVER"
        private const val ZONE = "Asia/Tehran"
    }

    private val db = NativeInboxDb(context)
    private val manager: AlarmManager? = context.getSystemService(AlarmManager::class.java)

    fun canScheduleExact(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) manager?.canScheduleExactAlarms() == true else true

    fun schedule(occurrenceUid: String, reminderId: String, rev: Long, title: String, at: Long, index: Int, followupCount: Int, intervalMin: Int, priority: Int) {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_FIRE
            data = Uri.parse("hamrah://alarm/$occurrenceUid/$index")
            putExtra("occurrenceUid", occurrenceUid)
            putExtra("reminderId", reminderId)
            putExtra("rev", rev)
            putExtra("title", title)
            putExtra("index", index)
            putExtra("followupCount", followupCount)
            putExtra("intervalMin", intervalMin)
            putExtra("priority", priority)
        }
        val pending = PendingIntent.getBroadcast(
            context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val am = manager ?: return
        val triggerAt = if (at < System.currentTimeMillis()) System.currentTimeMillis() + 1000 else at
        try {
            if (canScheduleExact()) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            }
            db.logEvent(DiagCodes.ALARM_SCHEDULED, "$index:${occurrenceUid.take(8)}")
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        }
    }

    fun cancel(occurrenceUid: String, followupCount: Int = Contract.MAX_FOLLOWUPS) {
        val am = manager ?: return
        for (index in 0..followupCount.coerceAtMost(Contract.MAX_FOLLOWUPS)) {
            val intent = Intent(context, AlarmReceiver::class.java).apply {
                action = ACTION_FIRE
                data = Uri.parse("hamrah://alarm/$occurrenceUid/$index")
                putExtra("occurrenceUid", occurrenceUid)
            }
            val pending = PendingIntent.getBroadcast(
                context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.cancel(pending)
        }
    }

    fun scheduleRollover() {
        val snapshot = NativeSnapshot.parse(db.snapshotJson())
        val (hour, minute) = snapshot.rolloverHourMinute()
        val zone = ZoneId.of(ZONE)
        val now = Instant.now().atZone(zone)
        var target = now.toLocalDate().atTime(hour, minute).atZone(zone)
        if (!target.toInstant().isAfter(now.toInstant())) target = target.plusDays(1)
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_ROLLOVER
            data = Uri.parse("hamrah://rollover")
        }
        val pending = PendingIntent.getBroadcast(
            context, 1, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val am = manager ?: return
        try {
            if (canScheduleExact()) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target.toInstant().toEpochMilli(), pending)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target.toInstant().toEpochMilli(), pending)
            }
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target.toInstant().toEpochMilli(), pending)
        }
    }

    fun restoreAll() {
        var restored = 0
        for (alarm in db.pendingAlarms()) {
            if (alarm.scheduledFor > System.currentTimeMillis()) {
                schedule(
                    alarm.occurrenceUid, alarm.reminderId, alarm.rev, alarm.title, alarm.scheduledFor,
                    alarm.followupsSent, alarm.followupCount, alarm.followupIntervalMin, alarm.priority
                )
                restored++
            }
        }
        db.logEvent(DiagCodes.ALARM_RESTORED, restored.toString())
    }

    /** Moves yesterday's unfinished occurrences to today's same clock time. */
    fun rolloverCatchUp(now: Long = System.currentTimeMillis()) {
        val startOfToday = PersianFormat.startOfDayMillis(now)
        val overdue = db.pendingAlarmsBefore(startOfToday)
        for (alarm in overdue) {
            db.setAlarmStatus(alarm.occurrenceUid, "rolled_over")
            db.insertOutcome(alarm.occurrenceUid, alarm.reminderId, alarm.rev, "rolled_over", null)
            val clock = Instant.ofEpochMilli(alarm.scheduledFor).atZone(ZoneId.of(ZONE))
            val nextDay = LocalDate.ofInstant(Instant.ofEpochMilli(startOfToday), ZoneId.of(ZONE))
            var target = nextDay.atTime(clock.hour, clock.minute).atZone(ZoneId.of(ZONE)).toInstant().toEpochMilli()
            if (target <= now) target += Contract.DAY_MS
            val existing = db.pendingAlarms().any {
                it.reminderId == alarm.reminderId && it.scheduledFor == target
            }
            if (!existing) {
                val uid = UUID.randomUUID().toString()
                db.upsertAlarm(uid, alarm.reminderId, alarm.rev + 1, alarm.title, target,
                    alarm.followupCount, alarm.followupIntervalMin, alarm.priority)
                db.insertOccurrenceEvent(uid, alarm.reminderId, alarm.rev + 1, alarm.title, target, "rolled_over")
                schedule(uid, alarm.reminderId, alarm.rev + 1, alarm.title, target, 0,
                    alarm.followupCount, alarm.followupIntervalMin, alarm.priority)
                db.logEvent(DiagCodes.ALARM_ROLLOVER, alarm.occurrenceUid.take(8))
            }
        }
    }
}

class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val scheduler = AlarmScheduler(context)
        val db = NativeInboxDb(context)
        Thread {
            try {
                when (intent.action) {
                    AlarmScheduler.ACTION_ROLLOVER -> {
                        scheduler.rolloverCatchUp()
                        scheduler.scheduleRollover()
                    }
                    AlarmScheduler.ACTION_FIRE -> {
                        val occurrenceUid = intent.getStringExtra("occurrenceUid") ?: return@Thread
                        val index = intent.getIntExtra("index", 0)
                        val alarm = db.alarm(occurrenceUid) ?: return@Thread
                        if (alarm.status != "pending" && alarm.status != "deferred") return@Thread
                        showReminder(context, alarm, index)
                        val sent = maxOf(alarm.followupsSent, index + 1)
                        db.setFollowupsSent(occurrenceUid, sent)
                        if (sent < alarm.followupCount && sent <= Contract.MAX_FOLLOWUPS) {
                            val nextAt = System.currentTimeMillis() + alarm.followupIntervalMin * 60_000L
                            scheduler.schedule(alarm.occurrenceUid, alarm.reminderId, alarm.rev, alarm.title,
                                nextAt, sent, alarm.followupCount, alarm.followupIntervalMin, alarm.priority)
                        }
                        db.logEvent(DiagCodes.ALARM_FIRED, "$index:${occurrenceUid.take(8)}")
                    }
                }
            } finally {
                pending.finish()
            }
        }.start()
    }

    private fun showReminder(context: Context, alarm: NativeInboxDb.AlarmRow, index: Int) {
        NotificationChannels.ensure(context)
        if (NotificationManagerCompat.from(context).areNotificationsEnabled().not()) return
        val openIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("route", "/reminders")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPending = PendingIntent.getActivity(
            context, alarm.occurrenceUid.hashCode(), openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = NotificationCompat.Builder(context, NotificationChannels.REMINDER)
            .setSmallIcon(R.drawable.ic_stat_hamrah)
            .setContentTitle(if (index == 0) "یادآور" else "یادآوری دوباره")
            .setContentText(alarm.title)
            .setStyle(NotificationCompat.BigTextStyle().bigText(alarm.title))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(false)
            .setOngoing(false)
            .setContentIntent(openPending)
            .addAction(0, "انجام شد", action(context, alarm.occurrenceUid, AlarmActionReceiver.ACTION_DONE))
            .addAction(0, "۱۰ دقیقه بعد", action(context, alarm.occurrenceUid, AlarmActionReceiver.ACTION_SNOOZE))
            .addAction(0, "فردا", action(context, alarm.occurrenceUid, AlarmActionReceiver.ACTION_TOMORROW))
        NotificationManagerCompat.from(context).notify(alarm.occurrenceUid.hashCode(), builder.build())
    }

    private fun action(context: Context, occurrenceUid: String, action: String): PendingIntent {
        val intent = Intent(context, AlarmActionReceiver::class.java).apply {
            this.action = action
            putExtra("occurrenceUid", occurrenceUid)
        }
        return PendingIntent.getBroadcast(
            context, (occurrenceUid + action).hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}

class AlarmActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_DONE = "com.hamrah.app.action.ALARM_DONE"
        const val ACTION_SNOOZE = "com.hamrah.app.action.ALARM_SNOOZE"
        const val ACTION_TOMORROW = "com.hamrah.app.action.ALARM_TOMORROW"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val db = NativeInboxDb(context)
        val scheduler = AlarmScheduler(context)
        Thread {
            try {
                val uid = intent.getStringExtra("occurrenceUid") ?: return@Thread
                val alarm = db.alarm(uid) ?: return@Thread
                when (intent.action) {
                    ACTION_DONE -> {
                        db.insertOutcome(uid, alarm.reminderId, alarm.rev, "done", null)
                        db.setAlarmStatus(uid, "done")
                        scheduler.cancel(uid, alarm.followupCount)
                    }
                    ACTION_SNOOZE -> {
                        val at = System.currentTimeMillis() + Contract.SNOOZE_MINUTES * 60_000L
                        db.updateAlarmSchedule(uid, at, snoozeDelta = 1)
                        db.setFollowupsSent(uid, 0)
                        db.insertOccurrenceEvent(uid, alarm.reminderId, alarm.rev, alarm.title, at, "snoozed")
                        scheduler.schedule(uid, alarm.reminderId, alarm.rev, alarm.title, at, 0,
                            alarm.followupCount, alarm.followupIntervalMin, alarm.priority)
                    }
                    ACTION_TOMORROW -> {
                        db.insertOutcome(uid, alarm.reminderId, alarm.rev, "deferred_tomorrow", null)
                        db.setAlarmStatus(uid, "deferred")
                        scheduler.cancel(uid, alarm.followupCount)
                        val zone = ZoneId.of("Asia/Tehran")
                        val clock = Instant.ofEpochMilli(alarm.scheduledFor).atZone(zone)
                        val startToday = PersianFormat.startOfDayMillis(System.currentTimeMillis())
                        var target = LocalDate.ofInstant(Instant.ofEpochMilli(startToday), zone)
                            .plusDays(1).atTime(clock.hour, clock.minute).atZone(zone).toInstant().toEpochMilli()
                        val newUid = UUID.randomUUID().toString()
                        db.upsertAlarm(newUid, alarm.reminderId, alarm.rev + 1, alarm.title, target,
                            alarm.followupCount, alarm.followupIntervalMin, alarm.priority)
                        db.insertOccurrenceEvent(newUid, alarm.reminderId, alarm.rev + 1, alarm.title, target, "deferred_tomorrow")
                        scheduler.schedule(newUid, alarm.reminderId, alarm.rev + 1, alarm.title, target, 0,
                            alarm.followupCount, alarm.followupIntervalMin, alarm.priority)
                    }
                }
                NotificationManagerCompat.from(context).cancel(uid.hashCode())
            } finally {
                pending.finish()
            }
        }.start()
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val scheduler = AlarmScheduler(context)
        Thread {
            try {
                scheduler.rolloverCatchUp()
                scheduler.restoreAll()
                scheduler.scheduleRollover()
                com.hamrah.app.sms.SmsRecovery.run(context)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
