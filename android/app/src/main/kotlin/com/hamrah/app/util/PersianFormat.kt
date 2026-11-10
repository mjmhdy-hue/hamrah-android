package com.hamrah.app.util

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

/** Persian-digit and money presentation used by notifications and the native UI text. */
object PersianFormat {
    private val FA_DIGITS = charArrayOf('۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹')

    fun digits(input: String): String {
        val sb = StringBuilder(input.length)
        for (ch in input) {
            sb.append(if (ch in '0'..'9') FA_DIGITS[ch - '0'] else ch)
        }
        return sb.toString()
    }

    fun grouped(value: Long): String {
        val raw = value.toString()
        val sb = StringBuilder()
        for ((index, ch) in raw.withIndex()) {
            if (index > 0 && (raw.length - index) % 3 == 0) sb.append('\u066C')
            sb.append(ch)
        }
        return sb.toString()
    }

    fun money(amountRial: Long, unit: String): String {
        if (unit == "rial") return digits(grouped(amountRial)) + " ریال"
        val whole = amountRial / 10
        val remainder = amountRial % 10
        return if (remainder == 0L) {
            digits(grouped(whole)) + " تومان"
        } else {
            digits(grouped(whole)) + "." + digits(remainder.toString()) + " تومان"
        }
    }

    fun clock(epochMillis: Long, zone: String = "Asia/Tehran"): String {
        val z = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.of(zone))
        return digits(String.format(Locale.US, "%02d:%02d", z.hour, z.minute))
    }

    fun date(epochMillis: Long, zone: String = "Asia/Tehran"): String {
        val z = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.of(zone))
        val j = com.hamrah.app.core.Jalali.toJalali(z.year, z.monthValue, z.dayOfMonth)
        return digits(String.format(Locale.US, "%04d/%02d/%02d", j.year, j.month, j.day))
    }

    fun startOfDayMillis(epochMillis: Long, zone: String = "Asia/Tehran"): Long {
        val z = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.of(zone))
        return LocalDate.of(z.year, z.monthValue, z.dayOfMonth)
            .atStartOfDay(ZoneId.of(zone)).toInstant().toEpochMilli()
    }
}
