package com.hamrah.app.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** F03/F04: nothing personal or secret may survive into the body that is written to a database. */
class RedactionTest {

    private val bluDebit = """
        بلو
        برداشت پول
        زهرا عزیز، 900,000 ریال از حساب شما پرید.
        موجودی: 84,085 ریال
        16:33
        1405.08.01
    """.trimIndent()

    @Test
    fun `blu greeting name is replaced but the sentence stays parseable`() {
        val body = Normalizer.normalize(bluDebit)
        val before = SmsParser.parse("+989999987641", body, 0L)
        assertEquals(ParseStatus.PARSED, before.status)

        val redacted = Normalizer.redactPersonal(body)
        assertFalse(redacted.contains("زهرا"))
        assertTrue(redacted.contains("کاربر عزیز،"))
        assertTrue(redacted.contains("900,000"))

        // Redaction happens after parsing, so the stored body is what a human reads.
        val after = SmsParser.parse("+989999987641", redacted, 0L)
        assertEquals(900000L, after.tx?.amountRial)
    }

    @Test
    fun `otp bodies keep the mask and no digits from the code`() {
        val otp = """
            بلو
            بفرمایید رمز پویا
            زهرا عزیز،
            فروشگاه دیجی‌کالا
            مبلغ: 1,250,000 ریال
            رمز: 483920
            14:07
        """.trimIndent()
        val outcome = SmsParser.parse("+989999987641", Normalizer.normalize(otp), 0L)
        assertEquals(ParseStatus.OTP, outcome.status)
        assertFalse(outcome.persistedBody.contains("483920"))
        assertFalse(outcome.persistedBody.contains("زهرا"))
    }

    @Test
    fun `redaction is a no-op for messages without a greeting`() {
        val text = "بلو\nبرداشت پول\n900,000 ریال از حساب شما پرید.\nموجودی: 84,085 ریال\n16:33\n1405.08.01"
        assertEquals(text, Normalizer.redactPersonal(text))
    }
}
