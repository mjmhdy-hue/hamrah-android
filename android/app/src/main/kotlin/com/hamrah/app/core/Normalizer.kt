package com.hamrah.app.core

import java.security.MessageDigest

/**
 * Text normalization for SMS bodies before template matching and hashing.
 * Pure Kotlin: no Android dependencies, so it runs in JVM unit tests.
 */
object Normalizer {

    private const val ARABIC_YEH = '\u064A'
    private const val PERSIAN_YEH = '\u06CC'
    private const val ARABIC_KAF = '\u0643'
    private const val PERSIAN_KAF = '\u06A9'

    private val STRIPPED_CODEPOINTS = intArrayOf(
        0x200B, 0x200C, 0x200D, // ZWSP, ZWNJ, ZWJ
        0x200E, 0x200F,         // LRM, RLM
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E, // bidi embedding/override
        0x2060, 0x2066, 0x2067, 0x2068, 0x2069, // word joiner, bidi isolates
        0xFEFF                  // BOM
    )

    /** Blu sentences start with "<first name> عزیز،" — the name must never reach storage. */
    private val GREETING = Regex("^.*?\\s*عزیز،")

    /**
     * Removes the customer's first name from every line of an already-normalized body.
     * Call it *after* parsing: templates match the original text, storage gets the sanitized one.
     */
    fun redactPersonal(body: String): String {
        if (body.isEmpty()) return body
        return body.split('\n').joinToString("\n") { it.replace(GREETING, "کاربر عزیز،") }
    }

    fun normalize(raw: String): String {
        if (raw.isEmpty()) return ""
        val sb = StringBuilder(raw.length)
        var i = 0
        while (i < raw.length) {
            val cp = raw.codePointAt(i)
            val chars = Character.charCount(cp)
            when {
                STRIPPED_CODEPOINTS.contains(cp) -> Unit
                cp == 0x064A -> sb.append(PERSIAN_YEH)
                cp == 0x0643 -> sb.append(PERSIAN_KAF)
                cp in 0x06F0..0x06F9 -> sb.append(('0' + (cp - 0x06F0)))
                cp in 0x0660..0x0669 -> sb.append(('0' + (cp - 0x0660)))
                cp == 0x066C -> sb.append(',')
                cp == 0x066B -> sb.append('.')
                cp == 0x00A0 -> sb.append(' ')
                cp == 0x000D -> Unit // normalize CRLF / CR to LF
                else -> sb.appendCodePoint(cp)
            }
            i += chars
        }
        val lines = sb.toString().split('\n')
        val out = ArrayList<String>(lines.size)
        // Empty lines carry no information and would break the exact-line-count templates.
        for (line in lines) {
            val collapsed = collapse(line.trim())
            if (collapsed.isNotEmpty()) out.add(collapsed)
        }
        return out.joinToString("\n")
    }

    private fun collapse(line: String): String {
        val sb = StringBuilder(line.length)
        var previousSpace = false
        for (ch in line) {
            val isSpace = ch == ' ' || ch == '\t' || ch == '\u000B' || ch == '\u000C'
            if (isSpace) {
                if (!previousSpace) sb.append(' ')
                previousSpace = true
            } else {
                sb.append(ch)
                previousSpace = false
            }
        }
        return sb.toString()
    }

    /** SHA-256(canonicalSender + "\n" + normalizedBody), lowercase hex. */
    fun smsHash(canonicalSender: String, normalizedBody: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val bytes = digest.digest((canonicalSender + "\n" + normalizedBody).toByteArray(Charsets.UTF_8))
        val hex = StringBuilder(bytes.size * 2)
        for (b in bytes) hex.append(String.format("%02x", b))
        return hex.toString()
    }

    /** Sender canonicalization: remove spaces/dashes, one leading +/00, one leading 98, one leading 0. */
    fun canonicalSender(address: String): String {
        var s = address.replace(" ", "").replace("-", "").trim()
        if (s.startsWith("+")) s = s.substring(1)
        else if (s.startsWith("00")) s = s.substring(2)
        if (s.startsWith("98") && s.length > 2) s = s.substring(2)
        if (s.startsWith("0") && s.length > 1) s = s.substring(1)
        return s
    }

    /** Masks every digit run of length 4..8 (used for OTP-like messages). */
    fun maskDigitRuns(body: String): String {
        val sb = StringBuilder(body.length)
        var i = 0
        while (i < body.length) {
            val ch = body[i]
            if (ch in '0'..'9') {
                var j = i
                while (j < body.length && body[j] in '0'..'9') j++
                val run = j - i
                if (run in 4..8) repeat(run) { sb.append('\u2022') } else sb.append(body, i, j)
                i = j
            } else {
                sb.append(ch)
                i++
            }
        }
        return sb.toString()
    }
}
