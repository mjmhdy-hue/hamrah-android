package com.hamrah.app.core

import java.io.File
import java.time.Instant

/**
 * Fixture-driven checks for the pure-Kotlin core. Shared by the JUnit suite and by
 * tools/Verify.kt so the exact same assertions run in CI and stand-alone.
 */
object FixtureChecks {

    data class Expect(
        val id: String,
        val status: ParseStatus,
        val direction: Direction? = null,
        val amount: Long? = null,
        val balance: Long? = null,
        val accountHint: String? = null,
        val label: String? = null,
        val purpose: String? = null,
        val occurredAtUtc: String? = null,
        val jalali: Triple<Int, Int, Int>? = null,
        val clock: Pair<Int, Int>? = null
    )

    private val expectations = listOf(
        Expect("M1", ParseStatus.PARSED, Direction.OUT, 300_000, 2_404_048, "55555", "برداشت",
            occurredAtUtc = "2026-10-31T17:45:00Z", jalali = Triple(1405, 8, 9), clock = 21 to 15),
        Expect("M2", ParseStatus.PARSED, Direction.OUT, 1_000_000, 1_404_048, "55555", "برداشت",
            occurredAtUtc = "2026-10-31T17:59:00Z", jalali = Triple(1405, 8, 9), clock = 21 to 29),
        Expect("M3", ParseStatus.PARSED, Direction.OUT, 1_333_500, 70_548, "55555", "خرید اینترنتی",
            occurredAtUtc = "2026-11-07T11:46:00Z", jalali = Triple(1405, 8, 16), clock = 15 to 16),
        Expect("M4", ParseStatus.PARSED, Direction.IN, 410_764_899, 410_786_048, "55555", "حقوق",
            occurredAtUtc = "2026-10-31T07:34:00Z", jalali = Triple(1405, 8, 9), clock = 11 to 4),
        Expect("M5", ParseStatus.PARSED, Direction.OUT, 410_000_000, 786_048, "55555", "حواله پل",
            occurredAtUtc = "2026-10-31T07:38:00Z", jalali = Triple(1405, 8, 9), clock = 11 to 8),
        Expect("M6", ParseStatus.PARSED, Direction.IN, 2_000_000, 2_704_048, "55555", "حواله پل",
            occurredAtUtc = "2026-10-31T17:44:00Z", jalali = Triple(1405, 8, 9), clock = 21 to 14),
        Expect("B1", ParseStatus.PARSED, Direction.OUT, 2_600_000, 50_038_727, "", "برداشت پول",
            occurredAtUtc = "2026-11-06T08:35:00Z", jalali = Triple(1405, 8, 15), clock = 12 to 5),
        Expect("B2", ParseStatus.PARSED, Direction.OUT, 18_000_000, 32_038_727, "", "برداشت پول",
            occurredAtUtc = "2026-11-06T09:02:00Z", jalali = Triple(1405, 8, 15), clock = 12 to 32),
        Expect("B3", ParseStatus.PARSED, Direction.OUT, 900_000, 84_085, "", "برداشت پول",
            occurredAtUtc = "2026-10-23T13:03:00Z", jalali = Triple(1405, 8, 1), clock = 16 to 33),
        Expect("B4", ParseStatus.PARSED, Direction.IN, 200_000, 284_085, "", "واریز پول",
            occurredAtUtc = "2026-10-23T15:02:00Z", jalali = Triple(1405, 8, 1), clock = 18 to 32),
        Expect("B5", ParseStatus.PARSED, Direction.OUT, 245_300, 38_785, "", "خرید بسته اینترنت",
            purpose = "خرید بسته اینترنت", occurredAtUtc = "2026-10-23T15:03:00Z",
            jalali = Triple(1405, 8, 1), clock = 18 to 33),
        Expect("B6", ParseStatus.PARSED, Direction.IN, 10_000_000, 10_038_785, "", "واریز پول",
            occurredAtUtc = "2026-10-26T16:44:00Z", jalali = Triple(1405, 8, 4), clock = 20 to 14),
        Expect("B7", ParseStatus.OTP, occurredAtUtc = "2026-10-26T19:18:00Z",
            jalali = Triple(1405, 8, 4), clock = 22 to 48),
        Expect("B8", ParseStatus.PARSED, Direction.OUT, 468_710, 9_570_075, "", "برداشت پول",
            occurredAtUtc = "2026-10-26T19:19:00Z", jalali = Triple(1405, 8, 4), clock = 22 to 49),
        Expect("B9", ParseStatus.PARSED, Direction.OUT, 245_300, 2_112_437, "", "خرید بسته اینترنت",
            purpose = "خرید بسته اینترنت", occurredAtUtc = "2026-11-09T14:53:00Z",
            jalali = Triple(1405, 8, 18), clock = 18 to 23),
        Expect("B10", ParseStatus.PARSED, Direction.OUT, 245_300, 1_867_137, "", "خرید بسته اینترنت",
            purpose = "خرید بسته اینترنت", occurredAtUtc = "2026-11-09T20:07:00Z",
            jalali = Triple(1405, 8, 18), clock = 23 to 37)
    )

    private fun senderFor(id: String): String = if (id.startsWith("M")) "9830009417" else "+989999987641"

    private fun receivedAtFor(e: Expect): Long {
        val (jy, jm, jd) = e.jalali!!
        val (hour, minute) = e.clock!!
        return Jalali.toEpochMillis(jy, jm, jd, hour, minute)
    }

    fun run(fixturesDir: File): List<String> {
        val failures = ArrayList<String>()
        fun check(condition: Boolean, message: String) {
            if (!condition) failures.add(message)
        }

        // Jalali vectors from the specification.
        val vectors = listOf(
            Triple(1405, 8, 1) to "2026-10-23",
            Triple(1405, 8, 4) to "2026-10-26",
            Triple(1405, 8, 9) to "2026-10-31",
            Triple(1405, 8, 15) to "2026-11-06",
            Triple(1405, 8, 16) to "2026-11-07",
            Triple(1405, 8, 18) to "2026-11-09"
        )
        for ((j, expected) in vectors) {
            val g = Jalali.toGregorian(j.first, j.second, j.third)
            val actual = "%04d-%02d-%02d".format(g.year, g.month, g.day)
            check(actual == expected, "jalali vector $j -> $actual, expected $expected")
            val back = Jalali.toJalali(g.year, g.month, g.day)
            check(back == Jalali.JDate(j.first, j.second, j.third), "jalali round-trip $j -> $back")
        }

        // Sender canonicalization.
        check(Normalizer.canonicalSender("+989999987641") == "9999987641", "canonical blu with +98")
        check(Normalizer.canonicalSender("09999987641") == "9999987641", "canonical blu national")
        check(Normalizer.canonicalSender("98-999-998-7641") == "9999987641", "canonical blu separators")
        check(Normalizer.canonicalSender("00989999987641") == "9999987641", "canonical blu 00 prefix")
        check(Normalizer.canonicalSender("9830009417") == Normalizer.canonicalSender("9830009417"), "canonical melli stable")

        for (e in expectations) {
            val file = File(fixturesDir, "${e.id}.txt")
            if (!file.exists()) {
                failures.add("fixture missing: ${file.path}")
                continue
            }
            val raw = file.readText(Charsets.UTF_8)
            val outcome = SmsParser.parse(senderFor(e.id), raw, receivedAtFor(e))
            check(outcome.status == e.status, "${e.id}: status ${outcome.status}, expected ${e.status}")
            if (e.status != ParseStatus.PARSED) {
                if (e.id == "B7") {
                    check(outcome.tx == null, "B7: OTP must not create a transaction")
                    check(!Regex("[0-9]{4,8}").containsMatchIn(outcome.persistedBody.substringAfter("رمز:", "")),
                        "B7: OTP code still present in persisted body")
                    check(outcome.persistedBody.contains("\u2022\u2022\u2022\u2022\u2022\u2022"), "B7: code not masked")
                }
                continue
            }
            val tx = outcome.tx
            if (tx == null) {
                failures.add("${e.id}: parsed without transaction")
                continue
            }
            check(tx.direction == e.direction, "${e.id}: direction ${tx.direction}")
            check(tx.amountRial == e.amount, "${e.id}: amount ${tx.amountRial}")
            check(tx.balanceAfterRial == e.balance, "${e.id}: balance ${tx.balanceAfterRial}")
            check(tx.accountHint == e.accountHint, "${e.id}: hint '${tx.accountHint}'")
            check(tx.label == e.label, "${e.id}: label '${tx.label}'")
            check(tx.purposeText == e.purpose, "${e.id}: purpose '${tx.purposeText}'")
            check(tx.timeSource == "body", "${e.id}: timeSource ${tx.timeSource}")
            check(Instant.ofEpochMilli(tx.occurredAt).toString() == e.occurredAtUtc,
                "${e.id}: occurred ${Instant.ofEpochMilli(tx.occurredAt)}")
            check(tx.counterparty == null && tx.counterpartySource == null, "${e.id}: counterparty must be null")
        }

        // Balance chains: consecutive pairs with no gap.
        val byId = expectations.filter { it.status == ParseStatus.PARSED }.associateBy { it.id }
        val chains = listOf(
            listOf("M6", "M1", "M2", "M3"),
            listOf("M4", "M5"),
            listOf("B1", "B2"),
            listOf("B3", "B4", "B5", "B6", "B8"),
            listOf("B9", "B10")
        )
        for (chain in chains) {
            for (i in 1 until chain.size) {
                val previous = byId[chain[i - 1]]!!
                val current = byId[chain[i]]!!
                val gap = BalanceBookkeeper.gap(previous.balance, current.balance!!, current.amount!!, current.direction!!)
                check(gap == 0L, "gap ${chain[i - 1]}->${chain[i]} = $gap, expected 0")
            }
        }
        val knownGap = BalanceBookkeeper.gap(byId["M5"]!!.balance, byId["M6"]!!.balance!!, byId["M6"]!!.amount!!, Direction.IN)
        check(knownGap == -82_000L, "known gap M5->M6 = $knownGap, expected -82000")

        // Dedupe: B9 and B10 must hash differently; re-delivery must hash identically.
        val b9 = File(fixturesDir, "B9.txt").readText(Charsets.UTF_8)
        val b10 = File(fixturesDir, "B10.txt").readText(Charsets.UTF_8)
        val canon = Normalizer.canonicalSender(senderFor("B9"))
        val hash9 = Normalizer.smsHash(canon, Normalizer.normalize(b9))
        val hash10 = Normalizer.smsHash(canon, Normalizer.normalize(b10))
        check(hash9 != hash10, "B9/B10 must have distinct sms_hash")
        check(hash9 == Normalizer.smsHash(canon, Normalizer.normalize(b9)), "sms_hash must be stable")
        check(hash9.matches(Regex("^[0-9a-f]{64}$")), "sms_hash must be 64 hex chars")

        // Year inference across a Jalali year boundary.
        val receivedLate1405 = Jalali.toEpochMillis(1405, 7, 28, 9, 0)
        val melliFuture = SmsParser.parse("9830009417",
            "بانك ملي ايران\nبرداشت:-1,000\nحساب:55555\nمانده:9,000\n0809-21:15", receivedLate1405)
        val inferred = melliFuture.tx?.let { Jalali.fromEpochMillis(it.occurredAt) }
        check(inferred == Jalali.JDate(1404, 8, 9), "year inference gave $inferred, expected 1404-08-09")

        // Unknown label -> unrecognized, never a transaction.
        val unknown = SmsParser.parse("9830009417",
            "بانك ملي ايران\nشارژ:-1,000\nحساب:55555\nمانده:9,000\n0809-21:15", receivedLate1405)
        check(unknown.status == ParseStatus.UNRECOGNIZED && unknown.errorCode == "unknown_label",
            "unknown label -> ${unknown.status}/${unknown.errorCode}")

        // Non-whitelisted sender is never parsed.
        val foreign = SmsParser.parse("+9821000000",
            "بانك ملي ايران\nبرداشت:-1,000\nحساب:55555\nمانده:9,000\n0809-21:15", receivedLate1405)
        check(foreign.status == ParseStatus.UNRECOGNIZED && foreign.errorCode == "unsupported_sender",
            "unsupported sender -> ${foreign.status}/${foreign.errorCode}")

        // OTP-like wording without the OTP shape must be masked and never parsed.
        val otpLike = SmsParser.parse("+989999987641", "بلو\nرمز پویا برای شما ارسال شد 123456", receivedLate1405)
        check(otpLike.status == ParseStatus.UNRECOGNIZED, "otp-like message parsed as ${otpLike.status}")
        check(!otpLike.persistedBody.contains("123456"), "otp-like code leaked: ${otpLike.persistedBody}")

        // Amount bounds.
        check(Money.parseAmount("9,223,372,036,854,775,808") == null, "int64 overflow must be rejected")
        check(Money.parseAmount("0") == null, "zero amount must be rejected")
        check(Money.parseAmount("-5,000") == null, "negative amount must be rejected")
        check(Money.parseBalance("0") == 0L, "zero balance must be accepted")

        // Multipart Persian text is joined before normalization; ZWNJ/bidi removal.
        val joined = Normalizer.normalize("بانك ملي\u200f ايران\r\n\r\nموجودی: 50,038,727 ریال\r\nمی\u200cخواهم")
        check(joined == "بانک ملی ایران\nموجودی: 50,038,727 ریال\nمیخواهم", "normalization got: $joined")

        return failures
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val dir = File(if (args.isNotEmpty()) args[0] else "test/fixtures/sms")
        val failures = run(dir)
        if (failures.isEmpty()) {
            println("ALL FIXTURE CHECKS PASSED (${expectations.size} fixtures)")
        } else {
            println("FAILURES (${failures.size}):")
            failures.forEach { println(" - $it") }
            kotlin.system.exitProcess(1)
        }
    }
}
