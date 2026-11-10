package com.hamrah.app.db

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.util.Log
import com.hamrah.app.Contract
import com.hamrah.app.crypto.KeyStoreManager
import net.zetetic.database.sqlcipher.SQLiteDatabase
import java.io.File
import java.util.UUID

class NativeDbUnavailableException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * The Kotlin-owned inbox/operational database. Only native code ever writes it; Flutter reads
 * events through drainInbox(). Encrypted with SQLCipher (SQLite3MultipleCiphers is not used here,
 * the two databases are independent on purpose).
 */
class NativeInboxDb(private val context: Context) {

    companion object {
        private const val TAG = "NativeInboxDb"
        private const val DB_NAME = "native_inbox.db"
        private const val SCHEMA_VERSION = 1
    }

    private var db: SQLiteDatabase? = null
    val databaseFile: File get() = File(context.getApplicationContext().noBackupFilesDir, DB_NAME)

    @Synchronized
    fun open(): SQLiteDatabase {
        db?.let { if (it.isOpen) return it }
        val passphrase = try {
            KeyStoreManager(context).nativePassphrase()
        } catch (e: Exception) {
            throw NativeDbUnavailableException("native_key", e)
        }
        val file = databaseFile
        file.parentFile?.mkdirs()
        val opened = try {
            SQLiteDatabase.openOrCreateDatabase(file, passphrase, null, null)
                ?: throw NativeDbUnavailableException("open_returned_null")
        } catch (e: Exception) {
            throw NativeDbUnavailableException("db_open", e)
        }
        opened.execSQL("PRAGMA foreign_keys = ON")
        opened.execSQL("PRAGMA journal_mode = WAL")
        val version = opened.rawQuery("PRAGMA user_version", null).use { c ->
            if (c.moveToFirst()) c.getInt(0) else 0
        }
        try {
            if (version < SCHEMA_VERSION) {
                opened.beginTransaction()
                try {
                    createSchema(opened)
                    opened.execSQL("PRAGMA user_version = $SCHEMA_VERSION")
                    opened.setTransactionSuccessful()
                } finally {
                    opened.endTransaction()
                }
            }
        } catch (e: Exception) {
            opened.close()
            throw NativeDbUnavailableException("migration", e)
        }
        db = opened
        Log.i(TAG, "native inbox opened (encrypted)")
        return opened
    }

    fun isOpen(): Boolean = db?.isOpen == true

    @Synchronized
    fun close() {
        db?.close()
        db = null
    }

    private fun createSchema(d: SQLiteDatabase) {
        d.execSQL(
            """
            CREATE TABLE IF NOT EXISTS sms_events(
                event_uid TEXT PRIMARY KEY,
                sender_raw TEXT NOT NULL,
                sender_canon TEXT NOT NULL,
                body TEXT NOT NULL,
                received_at INTEGER NOT NULL,
                part_count INTEGER NOT NULL DEFAULT 1,
                parse_status TEXT NOT NULL,
                template_id TEXT,
                bank_code TEXT,
                error_code TEXT,
                hash TEXT NOT NULL UNIQUE,
                notified INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL
            )
            """.trimIndent()
        )
        d.execSQL("CREATE INDEX IF NOT EXISTS idx_sms_received ON sms_events(received_at)")
        d.execSQL("CREATE INDEX IF NOT EXISTS idx_sms_status ON sms_events(parse_status)")
        d.execSQL(
            """
            CREATE TABLE IF NOT EXISTS tx_events(
                event_uid TEXT PRIMARY KEY,
                tx_uid TEXT NOT NULL UNIQUE,
                sms_event_uid TEXT NOT NULL,
                sms_hash TEXT NOT NULL,
                sender_canon TEXT NOT NULL,
                bank_code TEXT NOT NULL,
                account_hint TEXT NOT NULL,
                direction TEXT NOT NULL,
                amount_rial INTEGER NOT NULL,
                occurred_at INTEGER NOT NULL,
                time_source TEXT NOT NULL,
                counterparty TEXT,
                counterparty_source TEXT,
                purpose_text TEXT,
                label TEXT NOT NULL,
                balance_after_rial INTEGER NOT NULL,
                suggestion_key TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                batch_id TEXT,
                imported INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        d.execSQL("CREATE INDEX IF NOT EXISTS idx_tx_imported ON tx_events(imported)")
        d.execSQL(
            """
            CREATE TABLE IF NOT EXISTS resolutions(
                event_uid TEXT PRIMARY KEY,
                tx_uid TEXT NOT NULL,
                action TEXT NOT NULL,
                category_id TEXT,
                note TEXT,
                created_at INTEGER NOT NULL,
                batch_id TEXT,
                imported INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        d.execSQL(
            """
            CREATE TABLE IF NOT EXISTS alarms(
                occurrence_uid TEXT PRIMARY KEY,
                reminder_id TEXT NOT NULL,
                rev INTEGER NOT NULL,
                title TEXT NOT NULL,
                scheduled_for INTEGER NOT NULL,
                followup_count INTEGER NOT NULL DEFAULT 2,
                followup_interval_min INTEGER NOT NULL DEFAULT 15,
                followups_sent INTEGER NOT NULL DEFAULT 0,
                snooze_count INTEGER NOT NULL DEFAULT 0,
                snoozed_until INTEGER,
                priority INTEGER NOT NULL DEFAULT 1,
                status TEXT NOT NULL DEFAULT 'pending',
                updated_at INTEGER NOT NULL
            )
            """.trimIndent()
        )
        d.execSQL("CREATE INDEX IF NOT EXISTS idx_alarms_due ON alarms(status, scheduled_for)")
        d.execSQL(
            """
            CREATE TABLE IF NOT EXISTS outcome_events(
                event_uid TEXT PRIMARY KEY,
                occurrence_uid TEXT NOT NULL,
                reminder_id TEXT NOT NULL,
                rev INTEGER NOT NULL,
                outcome TEXT NOT NULL,
                snoozed_until INTEGER,
                resolved_at INTEGER NOT NULL,
                batch_id TEXT,
                imported INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        d.execSQL(
            """
            CREATE TABLE IF NOT EXISTS occurrence_events(
                event_uid TEXT PRIMARY KEY,
                occurrence_uid TEXT NOT NULL,
                reminder_id TEXT NOT NULL,
                rev INTEGER NOT NULL,
                title TEXT NOT NULL,
                scheduled_for INTEGER NOT NULL,
                reason TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                batch_id TEXT,
                imported INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        d.execSQL(
            """
            CREATE TABLE IF NOT EXISTS snapshot(
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            )
            """.trimIndent()
        )
        d.execSQL(
            """
            CREATE TABLE IF NOT EXISTS otp_hints(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                merchant TEXT NOT NULL,
                amount_rial INTEGER NOT NULL,
                hint_time INTEGER NOT NULL,
                expires_at INTEGER NOT NULL,
                used INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        d.execSQL(
            """
            CREATE TABLE IF NOT EXISTS diag_log(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                code TEXT NOT NULL,
                detail TEXT
            )
            """.trimIndent()
        )
    }

    // ---------------------------------------------------------------- sms events

    fun insertSmsEvent(
        eventUid: String,
        senderRaw: String,
        senderCanon: String,
        body: String,
        receivedAt: Long,
        partCount: Int,
        hash: String
    ): Boolean {
        val values = ContentValues().apply {
            put("event_uid", eventUid)
            put("sender_raw", senderRaw)
            put("sender_canon", senderCanon)
            put("body", body)
            put("received_at", receivedAt)
            put("part_count", partCount)
            put("parse_status", "received")
            put("hash", hash)
            put("created_at", System.currentTimeMillis())
        }
        val row = open().insertWithOnConflict("sms_events", null, values, SQLiteDatabase.CONFLICT_IGNORE)
        return row != -1L
    }

    fun updateSmsParse(
        eventUid: String,
        status: String,
        bankCode: String?,
        templateId: String?,
        errorCode: String?,
        body: String? = null,
        notified: Boolean = false
    ) {
        val values = ContentValues().apply {
            put("parse_status", status)
            put("bank_code", bankCode)
            put("template_id", templateId)
            put("error_code", errorCode)
            if (body != null) put("body", body)
            if (notified) put("notified", 1)
        }
        open().update("sms_events", values, "event_uid = ?", arrayOf(eventUid))
    }

    fun wasNotified(eventUid: String): Boolean =
        open().rawQuery("SELECT notified FROM sms_events WHERE event_uid = ?", arrayOf(eventUid)).use { c ->
            c.moveToFirst() && c.getInt(0) == 1
        }

    fun markNotified(eventUid: String) {
        open().update("sms_events", ContentValues().apply { put("notified", 1) }, "event_uid = ?", arrayOf(eventUid))
    }

    fun pendingRawEvents(limit: Int = 50): List<RawPending> {
        val sql = "SELECT event_uid, sender_raw, body, received_at FROM sms_events " +
            "WHERE parse_status = 'received' ORDER BY received_at ASC LIMIT ?"
        open().rawQuery(sql, arrayOf(limit.toString())).use { c ->
            val list = ArrayList<RawPending>(c.count)
            while (c.moveToNext()) {
                list.add(RawPending(c.getString(0), c.getString(1), c.getString(2), c.getLong(3)))
            }
            return list
        }
    }

    fun bodyForEvent(eventUid: String): String? =
        open().rawQuery("SELECT body FROM sms_events WHERE event_uid = ?", arrayOf(eventUid)).use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    data class RawPending(val eventUid: String, val sender: String, val body: String, val receivedAt: Long)

    // ---------------------------------------------------------------- tx events

    fun insertTxEvent(
        txUid: String,
        smsEventUid: String,
        smsHash: String,
        senderCanon: String,
        bankCode: String,
        accountHint: String,
        direction: String,
        amountRial: Long,
        occurredAt: Long,
        timeSource: String,
        counterparty: String?,
        counterpartySource: String?,
        purposeText: String?,
        label: String,
        balanceAfterRial: Long,
        suggestionKey: String
    ) {
        val values = ContentValues().apply {
            put("event_uid", txUid)
            put("tx_uid", txUid)
            put("sms_event_uid", smsEventUid)
            put("sms_hash", smsHash)
            put("sender_canon", senderCanon)
            put("bank_code", bankCode)
            put("account_hint", accountHint)
            put("direction", direction)
            put("amount_rial", amountRial)
            put("occurred_at", occurredAt)
            put("time_source", timeSource)
            put("counterparty", counterparty)
            put("counterparty_source", counterpartySource)
            put("purpose_text", purposeText)
            put("label", label)
            put("balance_after_rial", balanceAfterRial)
            put("suggestion_key", suggestionKey)
            put("created_at", System.currentTimeMillis())
        }
        open().insertWithOnConflict("tx_events", null, values, SQLiteDatabase.CONFLICT_IGNORE)
    }

    // ---------------------------------------------------------------- resolutions

    fun insertResolution(txUid: String, action: String, categoryId: String?, note: String?): String {
        val uid = UUID.randomUUID().toString()
        val values = ContentValues().apply {
            put("event_uid", uid)
            put("tx_uid", txUid)
            put("action", action)
            put("category_id", categoryId)
            put("note", note)
            put("created_at", System.currentTimeMillis())
        }
        open().insertWithOnConflict("resolutions", null, values, SQLiteDatabase.CONFLICT_IGNORE)
        return uid
    }

    // ---------------------------------------------------------------- snapshot

    fun putSnapshot(json: String) {
        val values = ContentValues().apply {
            put("key", "snapshot")
            put("value", json)
            put("updated_at", System.currentTimeMillis())
        }
        open().insertWithOnConflict("snapshot", null, values, SQLiteDatabase.CONFLICT_REPLACE)
    }

    fun snapshotJson(): String? =
        open().rawQuery("SELECT value FROM snapshot WHERE key = 'snapshot'", null).use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    // ---------------------------------------------------------------- alarms

    fun upsertAlarm(
        occurrenceUid: String,
        reminderId: String,
        rev: Long,
        title: String,
        scheduledFor: Long,
        followupCount: Int,
        followupIntervalMin: Int,
        priority: Int
    ): Boolean {
        val stored = open().rawQuery(
            "SELECT rev, status FROM alarms WHERE occurrence_uid = ?", arrayOf(occurrenceUid)
        ).use { c -> if (c.moveToFirst()) c.getLong(0) to c.getString(1) else null }
        if (stored != null) {
            if (stored.first > rev) return false
            // A resolved occurrence must not be resurrected by a stale Flutter re-sync.
            if (stored.second != "pending" && stored.first >= rev) return false
        }
        val values = ContentValues().apply {
            put("occurrence_uid", occurrenceUid)
            put("reminder_id", reminderId)
            put("rev", rev)
            put("title", title)
            put("scheduled_for", scheduledFor)
            put("followup_count", followupCount.coerceIn(0, Contract.MAX_FOLLOWUPS))
            put("followup_interval_min", followupIntervalMin.coerceAtLeast(1))
            put("priority", priority.coerceIn(0, 2))
            put("status", "pending")
            put("followups_sent", 0)
            putNull("snoozed_until")
            put("updated_at", System.currentTimeMillis())
        }
        open().insertWithOnConflict("alarms", null, values, SQLiteDatabase.CONFLICT_REPLACE)
        return true
    }

    fun setAlarmStatus(occurrenceUid: String, status: String) {
        open().update(
            "alarms",
            ContentValues().apply { put("status", status); put("updated_at", System.currentTimeMillis()) },
            "occurrence_uid = ?",
            arrayOf(occurrenceUid)
        )
    }

    fun updateAlarmSchedule(occurrenceUid: String, scheduledFor: Long, snoozeDelta: Int = 0) {
        val values = ContentValues().apply {
            put("scheduled_for", scheduledFor)
            put("snoozed_until", scheduledFor)
            put("updated_at", System.currentTimeMillis())
        }
        open().update("alarms", values, "occurrence_uid = ?", arrayOf(occurrenceUid))
        if (snoozeDelta > 0) {
            open().execSQL("UPDATE alarms SET snooze_count = snooze_count + $snoozeDelta WHERE occurrence_uid = ?",
                arrayOf(occurrenceUid))
        }
    }

    fun alarm(occurrenceUid: String): AlarmRow? =
        open().rawQuery("SELECT * FROM alarms WHERE occurrence_uid = ?", arrayOf(occurrenceUid)).use { c ->
            if (c.moveToFirst()) readAlarm(c) else null
        }

    fun pendingAlarms(): List<AlarmRow> {
        open().rawQuery("SELECT * FROM alarms WHERE status = 'pending' ORDER BY scheduled_for ASC", null).use { c ->
            val list = ArrayList<AlarmRow>(c.count)
            while (c.moveToNext()) list.add(readAlarm(c))
            return list
        }
    }

    fun pendingAlarmsBefore(before: Long): List<AlarmRow> {
        open().rawQuery(
            "SELECT * FROM alarms WHERE status = 'pending' AND scheduled_for < ? ORDER BY scheduled_for ASC",
            arrayOf(before.toString())
        ).use { c ->
            val list = ArrayList<AlarmRow>(c.count)
            while (c.moveToNext()) list.add(readAlarm(c))
            return list
        }
    }

    private fun readAlarm(c: Cursor) = AlarmRow(
        occurrenceUid = c.getString(c.getColumnIndexOrThrow("occurrence_uid")),
        reminderId = c.getString(c.getColumnIndexOrThrow("reminder_id")),
        rev = c.getLong(c.getColumnIndexOrThrow("rev")),
        title = c.getString(c.getColumnIndexOrThrow("title")),
        scheduledFor = c.getLong(c.getColumnIndexOrThrow("scheduled_for")),
        followupCount = c.getInt(c.getColumnIndexOrThrow("followup_count")),
        followupIntervalMin = c.getInt(c.getColumnIndexOrThrow("followup_interval_min")),
        followupsSent = c.getInt(c.getColumnIndexOrThrow("followups_sent")),
        snoozeCount = c.getInt(c.getColumnIndexOrThrow("snooze_count")),
        priority = c.getInt(c.getColumnIndexOrThrow("priority")),
        status = c.getString(c.getColumnIndexOrThrow("status"))
    )

    data class AlarmRow(
        val occurrenceUid: String,
        val reminderId: String,
        val rev: Long,
        val title: String,
        val scheduledFor: Long,
        val followupCount: Int,
        val followupIntervalMin: Int,
        val followupsSent: Int,
        val snoozeCount: Int,
        val priority: Int,
        val status: String
    )

    fun setFollowupsSent(occurrenceUid: String, sent: Int) {
        open().update(
            "alarms",
            ContentValues().apply { put("followups_sent", sent); put("updated_at", System.currentTimeMillis()) },
            "occurrence_uid = ?",
            arrayOf(occurrenceUid)
        )
    }

    fun insertOutcome(occurrenceUid: String, reminderId: String, rev: Long, outcome: String, snoozedUntil: Long?): String {
        val uid = UUID.randomUUID().toString()
        val values = ContentValues().apply {
            put("event_uid", uid)
            put("occurrence_uid", occurrenceUid)
            put("reminder_id", reminderId)
            put("rev", rev)
            put("outcome", outcome)
            put("snoozed_until", snoozedUntil)
            put("resolved_at", System.currentTimeMillis())
        }
        open().insertWithOnConflict("outcome_events", null, values, SQLiteDatabase.CONFLICT_IGNORE)
        return uid
    }

    fun insertOccurrenceEvent(
        occurrenceUid: String,
        reminderId: String,
        rev: Long,
        title: String,
        scheduledFor: Long,
        reason: String
    ): String {
        val uid = UUID.randomUUID().toString()
        val values = ContentValues().apply {
            put("event_uid", uid)
            put("occurrence_uid", occurrenceUid)
            put("reminder_id", reminderId)
            put("rev", rev)
            put("title", title)
            put("scheduled_for", scheduledFor)
            put("reason", reason)
            put("created_at", System.currentTimeMillis())
        }
        open().insertWithOnConflict("occurrence_events", null, values, SQLiteDatabase.CONFLICT_IGNORE)
        return uid
    }

    // ---------------------------------------------------------------- otp hints

    fun insertOtpHint(merchant: String, amountRial: Long, hintTime: Long) {
        val values = ContentValues().apply {
            put("merchant", merchant)
            put("amount_rial", amountRial)
            put("hint_time", hintTime)
            put("expires_at", hintTime + Contract.OTP_HINT_TTL_MS)
        }
        open().insert("otp_hints", null, values)
    }

    fun takeOtpHint(amountRial: Long, now: Long): String? {
        open().rawQuery(
            "SELECT id, merchant FROM otp_hints WHERE amount_rial = ? AND used = 0 AND expires_at >= ? " +
                "ORDER BY hint_time DESC LIMIT 1",
            arrayOf(amountRial.toString(), now.toString())
        ).use { c ->
            return if (c.moveToFirst()) {
                val id = c.getLong(0)
                val merchant = c.getString(1)
                open().update("otp_hints", ContentValues().apply { put("used", 1) }, "id = ?", arrayOf(id.toString()))
                merchant
            } else null
        }
    }

    fun pruneOtpHints(now: Long) {
        open().delete("otp_hints", "expires_at < ? OR used = 1", arrayOf(now.toString()))
    }

    // ---------------------------------------------------------------- import batches

    fun drainEvents(limit: Int): DrainBatch {
        val batchId = UUID.randomUUID().toString()
        val db = open()
        db.beginTransaction()
        try {
            val sms = ArrayList<Map<String, Any?>>()
            db.rawQuery(
                "SELECT * FROM sms_events WHERE event_uid IN (" +
                    "SELECT sms_event_uid FROM tx_events WHERE imported = 0 LIMIT ?" +
                    ") OR (parse_status IN ('unrecognized','otp') AND event_uid IN (" +
                    "SELECT event_uid FROM sms_events WHERE parse_status IN ('unrecognized','otp') " +
                    "ORDER BY received_at DESC LIMIT ?))",
                arrayOf(limit.toString(), limit.toString())
            ).use { c ->
                while (c.moveToNext()) sms.add(mapOf(
                    "eventUid" to c.getString(c.getColumnIndexOrThrow("event_uid")),
                    "sender" to c.getString(c.getColumnIndexOrThrow("sender_canon")),
                    "body" to c.getString(c.getColumnIndexOrThrow("body")),
                    "receivedAt" to c.getLong(c.getColumnIndexOrThrow("received_at")),
                    "parseStatus" to c.getString(c.getColumnIndexOrThrow("parse_status")),
                    "templateId" to c.getString(c.getColumnIndexOrThrow("template_id")),
                    "bankCode" to c.getString(c.getColumnIndexOrThrow("bank_code")),
                    "errorCode" to c.getString(c.getColumnIndexOrThrow("error_code")),
                    "hash" to c.getString(c.getColumnIndexOrThrow("hash")),
                    "partCount" to c.getInt(c.getColumnIndexOrThrow("part_count"))
                ))
            }

            val txs = ArrayList<Map<String, Any?>>()
            db.rawQuery("SELECT * FROM tx_events WHERE imported = 0 ORDER BY occurred_at ASC LIMIT ?",
                arrayOf(limit.toString())).use { c ->
                while (c.moveToNext()) txs.add(mapOf(
                    "eventUid" to c.getString(c.getColumnIndexOrThrow("event_uid")),
                    "txUid" to c.getString(c.getColumnIndexOrThrow("tx_uid")),
                    "smsEventUid" to c.getString(c.getColumnIndexOrThrow("sms_event_uid")),
                    "smsHash" to c.getString(c.getColumnIndexOrThrow("sms_hash")),
                    "bankCode" to c.getString(c.getColumnIndexOrThrow("bank_code")),
                    "accountHint" to c.getString(c.getColumnIndexOrThrow("account_hint")),
                    "direction" to c.getString(c.getColumnIndexOrThrow("direction")),
                    "amountRial" to c.getLong(c.getColumnIndexOrThrow("amount_rial")),
                    "occurredAt" to c.getLong(c.getColumnIndexOrThrow("occurred_at")),
                    "timeSource" to c.getString(c.getColumnIndexOrThrow("time_source")),
                    "counterparty" to c.getString(c.getColumnIndexOrThrow("counterparty")),
                    "counterpartySource" to c.getString(c.getColumnIndexOrThrow("counterparty_source")),
                    "purposeText" to c.getString(c.getColumnIndexOrThrow("purpose_text")),
                    "label" to c.getString(c.getColumnIndexOrThrow("label")),
                    "balanceAfterRial" to c.getLong(c.getColumnIndexOrThrow("balance_after_rial")),
                    "suggestionKey" to c.getString(c.getColumnIndexOrThrow("suggestion_key"))
                ))
            }

            val resolutions = ArrayList<Map<String, Any?>>()
            db.rawQuery("SELECT * FROM resolutions WHERE imported = 0 ORDER BY created_at ASC LIMIT ?",
                arrayOf(limit.toString())).use { c ->
                while (c.moveToNext()) resolutions.add(mapOf(
                    "eventUid" to c.getString(c.getColumnIndexOrThrow("event_uid")),
                    "txUid" to c.getString(c.getColumnIndexOrThrow("tx_uid")),
                    "action" to c.getString(c.getColumnIndexOrThrow("action")),
                    "categoryId" to c.getString(c.getColumnIndexOrThrow("category_id")),
                    "note" to c.getString(c.getColumnIndexOrThrow("note")),
                    "createdAt" to c.getLong(c.getColumnIndexOrThrow("created_at"))
                ))
            }

            val outcomes = ArrayList<Map<String, Any?>>()
            db.rawQuery("SELECT * FROM outcome_events WHERE imported = 0 ORDER BY resolved_at ASC LIMIT ?",
                arrayOf(limit.toString())).use { c ->
                while (c.moveToNext()) outcomes.add(mapOf(
                    "eventUid" to c.getString(c.getColumnIndexOrThrow("event_uid")),
                    "occurrenceUid" to c.getString(c.getColumnIndexOrThrow("occurrence_uid")),
                    "reminderId" to c.getString(c.getColumnIndexOrThrow("reminder_id")),
                    "rev" to c.getLong(c.getColumnIndexOrThrow("rev")),
                    "outcome" to c.getString(c.getColumnIndexOrThrow("outcome")),
                    "snoozedUntil" to c.getLong(c.getColumnIndexOrThrow("snoozed_until")),
                    "resolvedAt" to c.getLong(c.getColumnIndexOrThrow("resolved_at"))
                ))
            }

            val occurrences = ArrayList<Map<String, Any?>>()
            db.rawQuery("SELECT * FROM occurrence_events WHERE imported = 0 ORDER BY created_at ASC LIMIT ?",
                arrayOf(limit.toString())).use { c ->
                while (c.moveToNext()) occurrences.add(mapOf(
                    "eventUid" to c.getString(c.getColumnIndexOrThrow("event_uid")),
                    "occurrenceUid" to c.getString(c.getColumnIndexOrThrow("occurrence_uid")),
                    "reminderId" to c.getString(c.getColumnIndexOrThrow("reminder_id")),
                    "rev" to c.getLong(c.getColumnIndexOrThrow("rev")),
                    "title" to c.getString(c.getColumnIndexOrThrow("title")),
                    "scheduledFor" to c.getLong(c.getColumnIndexOrThrow("scheduled_for")),
                    "reason" to c.getString(c.getColumnIndexOrThrow("reason"))
                ))
            }

            if (sms.isNotEmpty()) markBatch(db, "sms_events", batchId, "event_uid", sms.map { it["eventUid"] as String })
            if (txs.isNotEmpty()) markBatch(db, "tx_events", batchId, "event_uid", txs.map { it["eventUid"] as String })
            if (resolutions.isNotEmpty()) markBatch(db, "resolutions", batchId, "event_uid", resolutions.map { it["eventUid"] as String })
            if (outcomes.isNotEmpty()) markBatch(db, "outcome_events", batchId, "event_uid", outcomes.map { it["eventUid"] as String })
            if (occurrences.isNotEmpty()) markBatch(db, "occurrence_events", batchId, "event_uid", occurrences.map { it["eventUid"] as String })
            db.setTransactionSuccessful()
            return DrainBatch(batchId, sms, txs, resolutions, outcomes, occurrences)
        } finally {
            db.endTransaction()
        }
    }

    private fun markBatch(db: SQLiteDatabase, table: String, batchId: String, column: String, ids: List<String>) {
        if (ids.isEmpty()) return
        db.beginTransaction()
        try {
            val stmt = db.compileStatement("UPDATE $table SET batch_id = ? WHERE $column = ?")
            for (id in ids) {
                stmt.clearBindings()
                stmt.bindString(1, batchId)
                stmt.bindString(2, id)
                stmt.execute()
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun ackBatch(batchId: String) {
        val db = open()
        db.beginTransaction()
        try {
            for (table in listOf("tx_events", "resolutions", "outcome_events", "occurrence_events")) {
                db.execSQL("UPDATE $table SET imported = 1 WHERE batch_id = ? AND imported = 0", arrayOf(batchId))
            }
            // sms_events has no imported column: the hash stays as the permanent dedupe record.
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    data class DrainBatch(
        val batchId: String,
        val sms: List<Map<String, Any?>>,
        val transactions: List<Map<String, Any?>>,
        val resolutions: List<Map<String, Any?>>,
        val outcomes: List<Map<String, Any?>>,
        val occurrences: List<Map<String, Any?>>
    )

    // ---------------------------------------------------------------- diagnostics

    fun logEvent(code: String, detail: String?, now: Long = System.currentTimeMillis()) {
        try {
            open().insert("diag_log", null, ContentValues().apply {
                put("ts", now)
                put("code", code)
                put("detail", detail)
            })
            if (rowsInDiagLog() > Contract.DIAG_RETENTION) {
                open().execSQL(
                    "DELETE FROM diag_log WHERE id <= (SELECT MAX(id) FROM diag_log) - ${Contract.DIAG_RETENTION - 200}"
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "diag write failed", e)
        }
    }

    private fun rowsInDiagLog(): Int =
        open().rawQuery("SELECT COUNT(*) FROM diag_log", null).use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }

    fun diagnostics(): Map<String, Any?> {
        val d = open()
        fun count(sql: String, args: Array<String>? = null): Long =
            d.rawQuery(sql, args).use { c -> if (c.moveToFirst()) c.getLong(0) else 0 }
        val lastSms = d.rawQuery(
            "SELECT received_at, parse_status, bank_code, error_code FROM sms_events ORDER BY received_at DESC LIMIT 1",
            null
        ).use { c ->
            if (c.moveToFirst()) mapOf(
                "receivedAt" to c.getLong(0),
                "status" to c.getString(1),
                "bankCode" to c.getString(2),
                "errorCode" to c.getString(3)
            ) else null
        }
        val logs = ArrayList<Map<String, Any?>>()
        d.rawQuery("SELECT ts, code, detail FROM diag_log ORDER BY id DESC LIMIT 200", null).use { c ->
            while (c.moveToNext()) logs.add(mapOf("ts" to c.getLong(0), "code" to c.getString(1), "detail" to c.getString(2)))
        }
        return mapOf(
            "nativeDbOpen" to isOpen(),
            "schemaVersion" to SCHEMA_VERSION,
            "smsCount" to count("SELECT COUNT(*) FROM sms_events"),
            "unrecognizedCount" to count("SELECT COUNT(*) FROM sms_events WHERE parse_status = 'unrecognized'"),
            "otpCount" to count("SELECT COUNT(*) FROM sms_events WHERE parse_status = 'otp'"),
            "pendingImport" to count("SELECT COUNT(*) FROM tx_events WHERE imported = 0"),
            "duplicates" to count("SELECT COUNT(*) FROM diag_log WHERE code = 'sms_duplicate'"),
            "pendingAlarms" to count("SELECT COUNT(*) FROM alarms WHERE status = 'pending'"),
            "lastSms" to lastSms,
            "log" to logs
        )
    }
}
