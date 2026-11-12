package com.hamrah.app.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import com.hamrah.app.DiagCodes
import com.hamrah.app.core.Direction
import com.hamrah.app.core.Normalizer
import com.hamrah.app.core.ParseOutcome
import com.hamrah.app.core.ParseStatus
import com.hamrah.app.core.SmsParser
import com.hamrah.app.db.NativeInboxDb
import com.hamrah.app.notify.TxNotifier
import java.util.UUID

/**
 * Native SMS path: whitelist -> normalize -> template -> dedupe -> persist -> notify.
 * Runs entirely without a Flutter engine.
 */
class SmsPipeline(private val context: Context) {

    private val db = NativeInboxDb(context)

    fun processIncoming(address: String, body: String, receivedAt: Long, partCount: Int) {
        if (body.isBlank()) return
        try {
            val snapshot = NativeSnapshot.parse(db.snapshotJson())
            val canonical = Normalizer.canonicalSender(address)
            if (!snapshot.isWhitelisted(canonical)) {
                // Non-whitelisted SMS is discarded before any persistence or content logging.
                db.logEvent(DiagCodes.SMS_DISCARDED_SENDER, "len:${body.length}")
                return
            }
            val normalized = Normalizer.normalize(body)
            if (normalized.isBlank()) return
            val hash = Normalizer.smsHash(canonical, normalized)
            // F03/F04: classify and redact BEFORE the first durable write. An OTP body is stored
            // only in its masked form and a Blu body loses the greeting name, so no code digits or
            // customer name ever reach a database, WAL frame or exported batch.
            val outcome = SmsParser.parse(address, normalized, receivedAt)
            val storedBody = Normalizer.redactPersonal(
                if (outcome.status == ParseStatus.OTP) outcome.persistedBody else normalized
            )
            val eventUid = UUID.randomUUID().toString()
            val stored = db.insertSmsEvent(
                eventUid = eventUid,
                senderRaw = address,
                senderCanon = canonical,
                body = storedBody,
                receivedAt = receivedAt,
                partCount = partCount,
                hash = hash,
                parseStatus = statusOf(outcome.status),
                bankCode = outcome.bankCode,
                templateId = outcome.templateId,
                errorCode = outcome.errorCode
            )
            if (!stored) {
                db.logEvent(DiagCodes.SMS_DUPLICATE, hash.take(8))
                return
            }
            db.logEvent(DiagCodes.SMS_RECEIVED, "$partCount:${hash.take(8)}")
            evaluate(eventUid, address, receivedAt, snapshot, normalized, hash, outcome)
        } catch (e: Exception) {
            Log.w("SmsPipeline", "processing failed", e)
            db.logEvent("sms_error", e.javaClass.simpleName)
        }
    }

    fun reprocess(eventUid: String, address: String, receivedAt: Long, normalized: String) {
        val snapshot = NativeSnapshot.parse(db.snapshotJson())
        val hash = Normalizer.smsHash(Normalizer.canonicalSender(address), normalized)
        if (normalized.isBlank()) return
        val outcome = SmsParser.parse(address, normalized, receivedAt)
        db.updateSmsParse(eventUid, statusOf(outcome.status), outcome.bankCode, outcome.templateId, outcome.errorCode)
        evaluate(eventUid, address, receivedAt, snapshot, normalized, hash, outcome)
    }

    private fun statusOf(status: ParseStatus): String = when (status) {
        ParseStatus.PARSED -> "parsed"
        ParseStatus.OTP -> "otp"
        ParseStatus.UNRECOGNIZED -> "unrecognized"
    }

    private fun evaluate(
        eventUid: String,
        address: String,
        receivedAt: Long,
        snapshot: NativeSnapshot,
        normalized: String,
        hash: String,
        outcome: ParseOutcome
    ) {
        when (outcome.status) {
            ParseStatus.PARSED -> {
                var tx = outcome.tx ?: return
                if (tx.bankCode == "blu" && tx.direction == Direction.OUT && tx.counterparty == null) {
                    val now = System.currentTimeMillis()
                    db.pruneOtpHints(now)
                    val hint = db.takeOtpHint(tx.amountRial, now)
                    if (hint != null) {
                        tx = tx.copy(counterparty = hint, counterpartySource = "otp_hint")
                    }
                }
                db.insertTxEvent(
                    txUid = eventUid,
                    smsEventUid = eventUid,
                    smsHash = hash,
                    senderCanon = Normalizer.canonicalSender(address),
                    bankCode = tx.bankCode,
                    accountHint = tx.accountHint,
                    direction = if (tx.direction == Direction.IN) "in" else "out",
                    amountRial = tx.amountRial,
                    occurredAt = tx.occurredAt,
                    timeSource = tx.timeSource,
                    counterparty = tx.counterparty,
                    counterpartySource = tx.counterpartySource,
                    purposeText = tx.purposeText,
                    label = tx.label,
                    balanceAfterRial = tx.balanceAfterRial,
                    suggestionKey = tx.suggestionKey
                )
                db.updateSmsParse(eventUid, "parsed", tx.bankCode, tx.templateId, null)
                db.logEvent(DiagCodes.SMS_PARSED, "${tx.templateId}:${tx.accountHint.takeLast(2)}")
                if (!db.wasNotified(eventUid)) {
                    val suggestions = snapshot.suggestions(tx.suggestionKey, tx.direction, tx.purposeText)
                    TxNotifier(context).notifyTx(
                        txUid = eventUid,
                        direction = if (tx.direction == Direction.IN) "in" else "out",
                        amountRial = tx.amountRial,
                        label = tx.label,
                        detail = tx.counterparty ?: tx.purposeText,
                        suggestions = suggestions,
                        snapshot = snapshot
                    )
                    db.markNotified(eventUid)
                }
            }
            ParseStatus.OTP -> {
                db.updateSmsParse(eventUid, "otp", outcome.bankCode, outcome.templateId, null)
                SmsParser.parseBluOtpHint(normalized, receivedAt)?.let { hint ->
                    db.insertOtpHint(hint.merchant, hint.amountRial, hint.hintTime)
                }
                // Never notified, never logged with content.
                db.logEvent(DiagCodes.SMS_OTP_SUPPRESSED, hash.take(8))
            }
            ParseStatus.UNRECOGNIZED -> {
                db.updateSmsParse(eventUid, "unrecognized", outcome.bankCode, null, outcome.errorCode)
                db.logEvent(DiagCodes.SMS_UNRECOGNIZED, outcome.errorCode)
            }
        }
    }
}

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val messages = try {
            Telephony.Sms.Intents.getMessagesFromIntent(intent)
        } catch (e: Exception) {
            null
        } ?: return
        if (messages.isEmpty()) return
        val address = messages.firstOrNull()?.originatingAddress?.takeIf { it.isNotBlank() } ?: return
        val body = messages.joinToString("") { it.messageBody ?: "" }
        if (body.isBlank()) return
        val partCount = messages.size
        val receivedAt = System.currentTimeMillis()
        val pending = goAsync()
        Thread {
            try {
                SmsPipeline(context).processIncoming(address, body, receivedAt, partCount)
            } catch (e: Exception) {
                Log.w("SmsReceiver", "receiver failure", e)
            } finally {
                pending.finish()
            }
        }.start()
    }
}

/** Recovery pass for events persisted but not parsed (process death between persist and parse). */
object SmsRecovery {
    fun run(context: Context) {
        try {
            val db = NativeInboxDb(context)
            val pending = db.pendingRawEvents(50)
            if (pending.isEmpty()) return
            val pipeline = SmsPipeline(context)
            for (event in pending) {
                pipeline.reprocess(event.eventUid, event.sender, event.receivedAt, event.body)
            }
            db.logEvent(DiagCodes.SMS_RECOVERY, pending.size.toString())
        } catch (e: Exception) {
            Log.w("SmsRecovery", "recovery failed", e)
        }
    }
}
