package com.hamrah.app

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.hamrah.app.crypto.KeyStoreManager
import com.hamrah.app.db.NativeInboxDb
import com.hamrah.app.sms.SmsPipeline
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Instrumented checks. They exercise the real receiver-side pipeline, the encrypted native store and
 * alarm bookkeeping on a device/emulator. Run with:
 *   flutter test integration_test  (or)
 *   .\gradlew.bat app:connectedDebugAndroidTest
 */
@RunWith(AndroidJUnit4::class)
class NativePipelineTest {

    private val context get() = ApplicationProvider.getApplicationContext<android.app.Application>()

    @Test
    fun nativeDatabaseIsEncrypted() {
        val db = NativeInboxDb(context)
        db.open()
        val file = db.databaseFile
        assertTrue(file.exists())
        val header = file.inputStream().use { input -> ByteArray(16).also { input.read(it) } }
        assertFalse("database file starts with a plain SQLite header", String(header, Charsets.US_ASCII).startsWith("SQLite format 3"))
        assertNotNull(KeyStoreManager(context).nativePassphrase())
    }

    @Test
    fun parsedSmsBecomesATransactionWithoutFlutter() {
        val pipeline = SmsPipeline(context)
        val body = "بلو\nبرداشت پول\nعلی عزیز، 2,600,000ریال از حساب شما پرید.\n" +
            "موجودی: 50,038,727 ریال\n12:05\n1405.08.15"
        pipeline.processIncoming("+989999987641", body, System.currentTimeMillis(), 1)
        val db = NativeInboxDb(context)
        val row = db.open().rawQuery(
            "SELECT amount_rial, direction, balance_after_rial FROM tx_events ORDER BY created_at DESC LIMIT 1",
            null
        ).use { c -> if (c.moveToFirst()) Triple(c.getLong(0), c.getString(1), c.getLong(2)) else null }
        assertNotNull(row)
        assertEquals(2_600_000L, row!!.first)
        assertEquals("out", row.second)
        assertEquals(50_038_727L, row.third)
    }

    @Test
    fun otpIsNeverStoredAsTransaction() {
        val pipeline = SmsPipeline(context)
        val body = "بلو\nبفرمایید رمز پویا\nخرید\nایرانسل\nمبلغ: 468,710 ریال\nرمز: 123456\n22:48"
        pipeline.processIncoming("+989999987641", body, System.currentTimeMillis(), 1)
        val db = NativeInboxDb(context)
        val row = db.open().rawQuery(
            "SELECT parse_status, body FROM sms_events WHERE hash IS NOT NULL ORDER BY created_at DESC LIMIT 1",
            null
        ).use { c -> if (c.moveToFirst()) c.getString(0) to c.getString(1) else null }
        assertNotNull(row)
        assertEquals("otp", row!!.first)
        assertFalse("OTP code leaked into persisted body", row.second.contains("123456"))
    }

    @Test
    fun nonWhitelistedSenderIsNotPersisted() {
        val db = NativeInboxDb(context)
        val before = db.diagnostics()["smsCount"]
        val pipeline = SmsPipeline(context)
        pipeline.processIncoming("+989120000000", "متن دلخواه ۱۲۳۴", System.currentTimeMillis(), 1)
        val after = db.diagnostics()["smsCount"]
        assertEquals(before, after)
    }

    @Test
    fun drainAndAckAreIdempotent() {
        val db = NativeInboxDb(context)
        val first = db.drainEvents(50)
        db.ackBatch(first.batchId)
        val second = db.drainEvents(50)
        assertTrue(second.transactions.isEmpty() || second.transactions.all { it["eventUid"] !in first.transactions.map { f -> f["eventUid"] } })
    }

    @Test
    fun wrongKeyCannotOpenExistingDatabase() {
        val file = NativeInboxDb(context).databaseFile
        assertTrue(file.exists())
        var failed = false
        try {
            net.zetetic.database.sqlcipher.SQLiteDatabase.openOrCreateDatabase(
                File(file.path), "definitely-not-the-key", null, null
            )?.rawQuery("SELECT COUNT(*) FROM sms_events", null)?.use { it.moveToFirst() }
        } catch (e: Exception) {
            failed = true
        }
        assertTrue("a wrong key must not open the database", failed)
    }
}
