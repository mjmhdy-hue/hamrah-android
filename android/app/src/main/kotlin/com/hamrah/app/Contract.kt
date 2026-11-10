package com.hamrah.app

/** Shared constants of the Flutter <-> native contract. */
object Contract {
    const val VERSION = 1

    const val CHANNEL = "com.hamrah.app/native"
    const val EVENTS_CHANNEL = "com.hamrah.app/events"

    const val PREFS = "hamrah_prefs"
    const val PREF_PENDING_ROUTE = "pending_route"

    const val DIAG_RETENTION = 2000
    const val OTP_HINT_TTL_MS = 15L * 60L * 1000L
    const val SNOOZE_MINUTES = 10L
    const val DAY_MS = 24L * 60L * 60L * 1000L
    const val MAX_FOLLOWUPS = 2
}

object DiagCodes {
    const val SMS_RECEIVED = "sms_received"
    const val SMS_DISCARDED_SENDER = "sms_discarded_sender"
    const val SMS_DUPLICATE = "sms_duplicate"
    const val SMS_PARSED = "sms_parsed"
    const val SMS_UNRECOGNIZED = "sms_unrecognized"
    const val SMS_OTP_SUPPRESSED = "sms_otp_suppressed"
    const val SMS_RECOVERY = "sms_recovery"
    const val TX_NOTIFIED = "tx_notified"
    const val TX_RESOLUTION = "tx_resolution"
    const val ALARM_SCHEDULED = "alarm_scheduled"
    const val ALARM_FIRED = "alarm_fired"
    const val ALARM_RESTORED = "alarm_restored"
    const val ALARM_ROLLOVER = "alarm_rollover"
    const val DB_OPENED = "db_opened"
    const val DB_OPEN_FAILED = "db_open_failed"
    const val KEY_FAILED = "key_failed"
    const val CONTRACT_MISMATCH = "contract_mismatch"
    const val IMPORT_DRAIN = "import_drain"
}
