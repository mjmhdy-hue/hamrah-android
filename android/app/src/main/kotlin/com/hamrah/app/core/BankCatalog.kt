package com.hamrah.app.core

/** Verified bank senders and message types. Anything else is unsupported. */
object BankCatalog {
    const val MELLI = "melli"
    const val BLU = "blu"

    data class Bank(
        val code: String,
        val nameFa: String,
        val seedSenders: List<String>,
        val verifiedTypesFa: List<String>
    )

    val banks: List<Bank> = listOf(
        Bank(
            code = MELLI,
            nameFa = "بانک ملی ایران",
            seedSenders = listOf("9830009417"),
            verifiedTypesFa = listOf("برداشت", "خرید اینترنتی", "حقوق", "حواله پل")
        ),
        Bank(
            code = BLU,
            nameFa = "بلو",
            seedSenders = listOf("+989999987641"),
            verifiedTypesFa = listOf("برداشت پول", "واریز پول", "خرید بسته اینترنت")
        )
    )

    fun bankForCanonicalSender(canonical: String): Bank? =
        banks.firstOrNull { bank ->
            bank.seedSenders.any { Normalizer.canonicalSender(it) == canonical }
        }

    fun bankByCode(code: String?): Bank? = banks.firstOrNull { it.code == code }

    fun isSupportedCanonicalSender(canonical: String): Boolean = bankForCanonicalSender(canonical) != null
}
