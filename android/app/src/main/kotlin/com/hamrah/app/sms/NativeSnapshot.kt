package com.hamrah.app.sms

import com.hamrah.app.core.Direction
import com.hamrah.app.core.Normalizer
import org.json.JSONArray
import org.json.JSONObject

/** In-memory view of the Flutter-owned configuration, pushed with syncSnapshot(). */
class NativeSnapshot private constructor(
    val categories: List<Category>,
    val memory: Map<String, String>,
    val whitelist: List<Sender>,
    val displayUnit: String,
    val hideAmounts: Boolean,
    val rolloverTime: String,
    val defaultFollowupCount: Int,
    val defaultFollowupIntervalMin: Int,
    val contractVersion: Int
) {
    data class Category(val id: String, val nameFa: String, val type: String)
    data class Sender(val address: String, val bankCode: String?, val enabled: Boolean)

    fun isWhitelisted(canonical: String): Boolean =
        whitelist.any { it.enabled && Normalizer.canonicalSender(it.address) == canonical }

    fun categoriesFor(direction: Direction): List<Category> {
        val wanted = if (direction == Direction.IN) "income" else "expense"
        return categories.filter { it.type == wanted }
    }

    fun suggestions(key: String, direction: Direction, purpose: String?): List<Category> {
        val available = categoriesFor(direction)
        if (available.isEmpty()) return emptyList()
        val result = ArrayList<Category>(2)
        memory[key]?.let { id -> available.firstOrNull { it.id == id }?.let { result.add(it) } }
        val haystack = (purpose ?: "") + " " + key
        for (rule in KEYWORD_RULES) {
            if (result.size >= 2) break
            if (!haystack.contains(rule.first)) continue
            available.firstOrNull { it.nameFa.contains(rule.second) && result.none { c -> c.id == it.id } }
                ?.let { result.add(it) }
        }
        return result.take(2)
    }

    fun rolloverHourMinute(): Pair<Int, Int> {
        val parts = rolloverTime.split(":")
        val h = parts.getOrNull(0)?.toIntOrNull()?.coerceIn(0, 23) ?: 23
        val m = parts.getOrNull(1)?.toIntOrNull()?.coerceIn(0, 59) ?: 59
        return h to m
    }

    companion object {
        private val KEYWORD_RULES = listOf(
            "اینترنت" to "اینترنت",
            "شارژ" to "اینترنت",
            "بسته" to "اینترنت",
            "قبض" to "قبوض",
            "برق" to "قبوض",
            "گاز" to "قبوض",
            "آب" to "قبوض",
            "بنزین" to "حمل",
            "تاکسی" to "حمل",
            "اسنپ" to "حمل",
            "میوه" to "خوراک",
            "رستوران" to "خوراک",
            "خرید" to "خرید",
            "دارو" to "سلامت",
            "حقوق" to "حقوق"
        )

        val DEFAULT = NativeSnapshot(
            categories = emptyList(),
            memory = emptyMap(),
            whitelist = listOf(
                Sender("9830009417", "melli", true),
                Sender("+989999987641", "blu", true)
            ),
            displayUnit = "toman",
            hideAmounts = false,
            rolloverTime = "23:59",
            defaultFollowupCount = 2,
            defaultFollowupIntervalMin = 15,
            contractVersion = 1
        )

        fun parse(json: String?): NativeSnapshot {
            if (json.isNullOrBlank()) return DEFAULT
            return try {
                val root = JSONObject(json)
                val categories = ArrayList<Category>()
                root.optJSONArray("categories")?.let { arr ->
                    for (i in 0 until arr.length()) {
                        val o = arr.getJSONObject(i)
                        categories.add(
                            Category(
                                id = o.getString("id"),
                                nameFa = o.getString("nameFa"),
                                type = o.optString("type", "expense")
                            )
                        )
                    }
                }
                val memory = HashMap<String, String>()
                root.optJSONObject("memory")?.let { obj ->
                    for (key in obj.keys()) memory[key] = obj.getString(key)
                }
                val whitelist = ArrayList<Sender>()
                root.optJSONArray("whitelist")?.let { arr ->
                    for (i in 0 until arr.length()) {
                        val o = arr.getJSONObject(i)
                        whitelist.add(
                            Sender(
                                address = o.getString("address"),
                                bankCode = if (o.isNull("bankCode")) null else o.optString("bankCode"),
                                enabled = o.optBoolean("enabled", true)
                            )
                        )
                    }
                }
                if (whitelist.isEmpty()) whitelist.addAll(DEFAULT.whitelist)
                val settings = root.optJSONObject("settings")
                NativeSnapshot(
                    categories = categories,
                    memory = memory,
                    whitelist = whitelist,
                    displayUnit = settings?.optString("displayUnit", "toman") ?: "toman",
                    hideAmounts = settings?.optBoolean("hideAmounts", false) ?: false,
                    rolloverTime = settings?.optString("rolloverTime", "23:59") ?: "23:59",
                    defaultFollowupCount = settings?.optInt("defaultFollowupCount", 2) ?: 2,
                    defaultFollowupIntervalMin = settings?.optInt("defaultFollowupIntervalMin", 15) ?: 15,
                    contractVersion = root.optInt("contractVersion", 1)
                )
            } catch (e: Exception) {
                DEFAULT
            }
        }

        fun emptyJson(categories: List<Category> = emptyList()): JSONObject = JSONObject().apply {
            put("contractVersion", 1)
            put("categories", JSONArray())
            put("memory", JSONObject())
            put("whitelist", JSONArray())
        }
    }
}
