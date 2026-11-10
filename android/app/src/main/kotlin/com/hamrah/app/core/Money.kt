package com.hamrah.app.core

/** Money parsing: int64 Rial only, never floating point. */
object Money {
    private const val MAX_RIAL = Long.MAX_VALUE

    /** Parses "2,404,048" style values. Returns null on empty/invalid/overflow/<=0. */
    fun parseAmount(raw: String?): Long? {
        if (raw == null) return null
        val cleaned = raw.replace(",", "").replace("\u066C", "").trim()
        if (cleaned.isEmpty()) return null
        if (!cleaned.all { it in '0'..'9' }) return null
        var value = 0L
        for (ch in cleaned) {
            val digit = ch - '0'
            if (value > (MAX_RIAL - digit) / 10) return null
            value = value * 10 + digit
        }
        return if (value > 0) value else null
    }

    /** Balance allows zero but nothing negative. */
    fun parseBalance(raw: String?): Long? {
        if (raw == null) return null
        val cleaned = raw.replace(",", "").replace("\u066C", "").trim()
        if (cleaned.isEmpty()) return null
        if (!cleaned.all { it in '0'..'9' }) return null
        var value = 0L
        for (ch in cleaned) {
            val digit = ch - '0'
            if (value > (MAX_RIAL - digit) / 10) return null
            value = value * 10 + digit
        }
        return value
    }
}
