package com.hamrah.app.core

enum class Direction { IN, OUT }

enum class ParseStatus { PARSED, UNRECOGNIZED, OTP }

data class ParsedTx(
    val bankCode: String,
    val label: String,
    val direction: Direction,
    val amountRial: Long,
    val balanceAfterRial: Long,
    val accountHint: String,
    val occurredAt: Long,
    val timeSource: String,
    val purposeText: String?,
    val counterparty: String?,
    val counterpartySource: String?,
    val templateId: String
) {
    val suggestionKey: String
        get() = normalizeKey(purposeText ?: label)

    companion object {
        fun normalizeKey(value: String): String = value.trim().replace("\u200c", " ")
    }
}

data class ParseOutcome(
    val status: ParseStatus,
    val tx: ParsedTx?,
    /** Body to persist: normalized for parsed/unrecognized, code-masked for OTP. */
    val persistedBody: String,
    val bankCode: String?,
    val templateId: String?,
    val errorCode: String?
) {
    companion object {
        fun unrecognized(body: String, bankCode: String?, code: String) =
            ParseOutcome(ParseStatus.UNRECOGNIZED, null, body, bankCode, null, code)
    }
}

/**
 * SMS template engine for the two verified banks only. Deviations from the literal regexes in
 * the specification are limited to tolerating optional spaces after ":" and inside the Blu
 * sentences; both were needed by the transcribed fixtures after normalization.
 */
object SmsParser {

    const val MELLI_TEMPLATE = "melli_v1"
    const val BLU_DEBIT_TEMPLATE = "blu_debit_v1"
    const val BLU_CREDIT_TEMPLATE = "blu_credit_v1"
    const val BLU_PURCHASE_TEMPLATE = "blu_purchase_v1"
    const val BLU_OTP_TEMPLATE = "blu_otp_v1"

    private val MELLI_HEADER = Regex("^بانک ملی ایران$")
    private val MELLI_AMOUNT = Regex("^(?<label>[^:\\n]+):\\s*(?<sign>[+-])(?<amount>[0-9,]+)$")
    private val MELLI_ACCOUNT = Regex("^حساب:(?<hint>[0-9]{3,8})$")
    private val MELLI_BALANCE = Regex("^مانده:(?<balance>[0-9,]+)$")
    private val MELLI_TIME = Regex("^(?<md>[0-9]{4})-(?<hm>[0-9]{2}:[0-9]{2})$")

    private val BLU_HEADER = Regex("^بلو$")
    private val BLU_DEBIT = Regex("^.*?عزیز،\\s*(?<amount>[0-9,]+)\\s*ریال\\s*از حساب شما پرید\\s*\\.?$")
    private val BLU_CREDIT = Regex("^.*?عزیز،\\s*(?<amount>[0-9,]+)\\s*ریال\\s*به حساب شما نشست\\s*\\.?$")
    private val BLU_PURCHASE = Regex(
        "^.*?عزیز،\\s*(?<amount>[0-9,]+)\\s*ریال\\s*بابت\\s*(?<purpose>.+?)\\s*از حساب شما پرید\\s*\\.?$"
    )
    private val BLU_BALANCE = Regex("^موجودی:\\s*(?<balance>[0-9,]+)\\s*ریال$")
    private val BLU_CLOCK = Regex("^(?<time>[0-9]{2}:[0-9]{2})$")
    private val BLU_DATE = Regex("^(?<date>[0-9]{4}\\.[0-9]{2}\\.[0-9]{2})$")

    private const val DAY_MS = 24L * 60L * 60L * 1000L
    private val MELLI_LABELS = setOf("برداشت", "خریداینترنتی", "حقوق", "حواله پل")

    fun parse(senderRaw: String, bodyRaw: String, receivedAt: Long, zoneId: String = "Asia/Tehran"): ParseOutcome {
        val canonical = Normalizer.canonicalSender(senderRaw)
        val bank = BankCatalog.bankForCanonicalSender(canonical)
        val body = Normalizer.normalize(bodyRaw)
        if (body.isEmpty()) {
            return ParseOutcome.unrecognized("", bank?.code, "empty_body")
        }
        if (body.contains("رمز")) {
            if (bank?.code == BankCatalog.BLU) {
                val otp = parseBluOtp(body)
                if (otp != null) return otp
            }
            return ParseOutcome.unrecognized(Normalizer.maskDigitRuns(body), bank?.code, "possible_otp")
        }
        if (bank == null) {
            return ParseOutcome.unrecognized(body, null, "unsupported_sender")
        }
        return when (bank.code) {
            BankCatalog.MELLI -> parseMelli(body, receivedAt, zoneId)
            BankCatalog.BLU -> parseBlu(body, receivedAt, zoneId)
            else -> ParseOutcome.unrecognized(body, bank.code, "unsupported_sender")
        }
    }

    private fun parseMelli(body: String, receivedAt: Long, zoneId: String): ParseOutcome {
        val lines = body.split('\n')
        if (lines.size != 5) return ParseOutcome.unrecognized(body, BankCatalog.MELLI, "shape")
        if (!MELLI_HEADER.matches(lines[0])) return ParseOutcome.unrecognized(body, BankCatalog.MELLI, "header")
        val amountMatch = MELLI_AMOUNT.find(lines[1])
            ?: return ParseOutcome.unrecognized(body, BankCatalog.MELLI, "amount_line")
        val label = amountMatch.groups["label"]!!.value.trim()
        if (label !in MELLI_LABELS) return ParseOutcome.unrecognized(body, BankCatalog.MELLI, "unknown_label")
        val shortLabel = if (label == "خریداینترنتی") "خرید اینترنتی" else label
        val amount = Money.parseAmount(amountMatch.groups["amount"]!!.value)
            ?: return ParseOutcome.unrecognized(body, BankCatalog.MELLI, "amount")
        val hint = MELLI_ACCOUNT.find(lines[2])?.groups?.get("hint")?.value
            ?: return ParseOutcome.unrecognized(body, BankCatalog.MELLI, "account")
        val balance = Money.parseBalance(MELLI_BALANCE.find(lines[3])?.groups?.get("balance")?.value)
            ?: return ParseOutcome.unrecognized(body, BankCatalog.MELLI, "balance")
        val timeMatch = MELLI_TIME.find(lines[4])
            ?: return ParseOutcome.unrecognized(body, BankCatalog.MELLI, "time")
        val md = timeMatch.groups["md"]!!.value
        val hm = timeMatch.groups["hm"]!!.value
        val month = md.substring(0, 2).toIntOrNull()
        val day = md.substring(2, 4).toIntOrNull()
        val hour = hm.substring(0, 2).toIntOrNull()
        val minute = hm.substring(3, 5).toIntOrNull()
            ?: return ParseOutcome.unrecognized(body, BankCatalog.MELLI, "time")

        var occurred = receivedAt
        var timeSource = "received"
        if (month != null && day != null && hour != null && hour in 0..23 && minute in 0..59) {
            val received = Jalali.fromEpochMillis(receivedAt, zoneId)
            var year = received.year
            var candidate = if (Jalali.isValid(year, month, day)) {
                Jalali.toEpochMillis(year, month, day, hour, minute, zoneId)
            } else null
            if (candidate == null) {
                // Invalid for this year (e.g. 12/30 in a non-leap year): try the previous year.
                year -= 1
                if (Jalali.isValid(year, month, day)) {
                    candidate = Jalali.toEpochMillis(year, month, day, hour, minute, zoneId)
                }
            }
            if (candidate != null) {
                if (candidate > receivedAt + 2 * DAY_MS) {
                    val previousYear = year - 1
                    if (Jalali.isValid(previousYear, month, day)) {
                        candidate = Jalali.toEpochMillis(previousYear, month, day, hour, minute, zoneId)
                    }
                }
                occurred = candidate
                timeSource = "body"
            }
        }

        val direction = if (amountMatch.groups["sign"]!!.value == "+") Direction.IN else Direction.OUT
        val tx = ParsedTx(
            bankCode = BankCatalog.MELLI,
            label = shortLabel,
            direction = direction,
            amountRial = amount,
            balanceAfterRial = balance,
            accountHint = hint,
            occurredAt = occurred,
            timeSource = timeSource,
            purposeText = null,
            counterparty = null,
            counterpartySource = null,
            templateId = MELLI_TEMPLATE
        )
        return ParseOutcome(ParseStatus.PARSED, tx, body, BankCatalog.MELLI, MELLI_TEMPLATE, null)
    }

    private fun parseBlu(body: String, receivedAt: Long, zoneId: String): ParseOutcome {
        val lines = body.split('\n')
        if (lines.size != 6) return ParseOutcome.unrecognized(body, BankCatalog.BLU, "shape")
        if (!BLU_HEADER.matches(lines[0])) return ParseOutcome.unrecognized(body, BankCatalog.BLU, "header")
        val type = lines[1]
        val sentence = lines[2]
        val template: String
        val direction: Direction
        val purpose: String?
        val amountMatch: MatchResult
        when (type) {
            "برداشت پول" -> {
                template = BLU_DEBIT_TEMPLATE
                direction = Direction.OUT
                purpose = null
                amountMatch = BLU_DEBIT.find(sentence)
                    ?: return ParseOutcome.unrecognized(body, BankCatalog.BLU, "sentence")
            }
            "واریز پول" -> {
                template = BLU_CREDIT_TEMPLATE
                direction = Direction.IN
                purpose = null
                amountMatch = BLU_CREDIT.find(sentence)
                    ?: return ParseOutcome.unrecognized(body, BankCatalog.BLU, "sentence")
            }
            "آنلاین شدی" -> {
                template = BLU_PURCHASE_TEMPLATE
                direction = Direction.OUT
                amountMatch = BLU_PURCHASE.find(sentence)
                    ?: return ParseOutcome.unrecognized(body, BankCatalog.BLU, "sentence")
                purpose = amountMatch.groups["purpose"]?.value?.trim()?.ifEmpty { null }
            }
            else -> return ParseOutcome.unrecognized(body, BankCatalog.BLU, "unknown_type")
        }
        val amount = Money.parseAmount(amountMatch.groups["amount"]?.value)
            ?: return ParseOutcome.unrecognized(body, BankCatalog.BLU, "amount")
        val balance = Money.parseBalance(BLU_BALANCE.find(lines[3])?.groups?.get("balance")?.value)
            ?: return ParseOutcome.unrecognized(body, BankCatalog.BLU, "balance")
        val clock = BLU_CLOCK.find(lines[4])?.groups?.get("time")?.value
            ?: return ParseOutcome.unrecognized(body, BankCatalog.BLU, "time")
        val dateText = BLU_DATE.find(lines[5])?.groups?.get("date")?.value
            ?: return ParseOutcome.unrecognized(body, BankCatalog.BLU, "date")
        val parts = dateText.split('.')
        val jy = parts[0].toIntOrNull() ?: return ParseOutcome.unrecognized(body, BankCatalog.BLU, "date")
        val jm = parts[1].toIntOrNull() ?: return ParseOutcome.unrecognized(body, BankCatalog.BLU, "date")
        val jd = parts[2].toIntOrNull() ?: return ParseOutcome.unrecognized(body, BankCatalog.BLU, "date")
        val hour = clock.substring(0, 2).toIntOrNull() ?: 0
        val minute = clock.substring(3, 5).toIntOrNull() ?: 0

        var occurred = receivedAt
        var timeSource = "received"
        if (Jalali.isValid(jy, jm, jd) && hour in 0..23 && minute in 0..59) {
            occurred = Jalali.toEpochMillis(jy, jm, jd, hour, minute, zoneId)
            timeSource = "body"
        }

        val label = when (type) {
            "برداشت پول" -> "برداشت پول"
            "واریز پول" -> "واریز پول"
            else -> "خرید بسته اینترنت"
        }
        val tx = ParsedTx(
            bankCode = BankCatalog.BLU,
            label = label,
            direction = direction,
            amountRial = amount,
            balanceAfterRial = balance,
            accountHint = "",
            occurredAt = occurred,
            timeSource = timeSource,
            purposeText = purpose,
            counterparty = null,
            counterpartySource = null,
            templateId = template
        )
        return ParseOutcome(ParseStatus.PARSED, tx, body, BankCatalog.BLU, template, null)
    }

    private fun parseBluOtp(body: String): ParseOutcome? {
        val lines = body.split('\n')
        if (lines.size != 7) return null
        if (!BLU_HEADER.matches(lines[0])) return null
        if (lines[1] != "بفرمایید رمز پویا") return null
        if (!Regex("^مبلغ:\\s*[0-9,]+\\s*ریال$").matches(lines[4])) return null
        if (!Regex("^رمز:\\s*[0-9]{4,8}$").matches(lines[5])) return null
        if (!Regex("^[0-9]{2}:[0-9]{2}$").matches(lines[6])) return null
        val masked = lines.toMutableList()
        masked[5] = "رمز: " + "\u2022".repeat(6)
        val persisted = masked.joinToString("\n")
        return ParseOutcome(ParseStatus.OTP, null, persisted, BankCatalog.BLU, BLU_OTP_TEMPLATE, null)
    }

    /** Extracts the merchant and amount from a Blu OTP for the optional P2 hint. */
    fun parseBluOtpHint(body: String, receivedAt: Long): OtpHint? {
        val lines = body.split('\n')
        if (lines.size != 7) return null
        if (lines[1] != "بفرمایید رمز پویا") return null
        val amount = Money.parseAmount(Regex("^مبلغ:\\s*([0-9,]+)").find(lines[4])?.groupValues?.getOrNull(1))
            ?: return null
        return OtpHint(merchant = lines[3].trim(), amountRial = amount, hintTime = receivedAt)
    }

    data class OtpHint(val merchant: String, val amountRial: Long, val hintTime: Long)
}

/** Balance gap bookkeeping, independent of storage so it can be unit tested. */
object BalanceBookkeeper {
    /** expected = previousBalance + signed amount; gap = actual - expected. */
    fun gap(previousBalance: Long?, actualBalance: Long, amount: Long, direction: Direction): Long? {
        if (previousBalance == null) return null
        val signed = if (direction == Direction.IN) amount else -amount
        return actualBalance - (previousBalance + signed)
    }
}
