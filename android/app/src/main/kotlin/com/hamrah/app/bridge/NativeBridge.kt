package com.hamrah.app.bridge

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.hamrah.app.Contract
import com.hamrah.app.DiagCodes
import com.hamrah.app.alarm.AlarmScheduler
import com.hamrah.app.crypto.KeyStoreManager
import com.hamrah.app.db.NativeDbUnavailableException
import com.hamrah.app.db.NativeInboxDb
import com.hamrah.app.notify.NotificationChannels
import com.hamrah.app.sms.SmsReceiver
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Typed Flutter <-> native contract (Pigeon contract described in pigeons/native_api.dart).
 * Implemented over MethodChannel so it also works in environments without code generation.
 */
class NativeBridge(
    private val context: Context,
    messenger: BinaryMessenger,
    private val activityProvider: () -> Activity?
) : MethodChannel.MethodCallHandler {

    companion object {
        @Volatile
        var activityRef: Activity? = null

        fun smsPermission(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

        fun notificationsPermission(context: Context): Boolean {
            val runtime = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
            } else true
            return runtime && NotificationManagerCompat.from(context).areNotificationsEnabled()
        }

        fun exactAlarmAllowed(context: Context): Boolean =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() == true
            } else true
    }

    private val channel = MethodChannel(messenger, Contract.CHANNEL)
    private val eventsChannel = MethodChannel(messenger, Contract.EVENTS_CHANNEL)
    private val db = NativeInboxDb(context)

    fun register() {
        channel.setMethodCallHandler(this)
        BridgeEvents.attach(eventsChannel)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getContractVersion" -> result.success(Contract.VERSION)
                "getDbKey" -> result.success(KeyStoreManager(context).mainPassphrase())
                "syncSnapshot" -> {
                    val json = call.argument<String>("json") ?: return result.error("bad_args", "json missing", null)
                    db.putSnapshot(json)
                    result.success(true)
                }
                "upsertAlarm" -> {
                    val json = call.argument<String>("json") ?: return result.error("bad_args", "json missing", null)
                    result.success(upsertAlarm(json))
                }
                "cancelAlarm" -> {
                    val uid = call.argument<String>("occurrenceUid") ?: return result.error("bad_args", "uid missing", null)
                    AlarmScheduler(context).cancel(uid)
                    db.setAlarmStatus(uid, "dismissed")
                    result.success(true)
                }
                "drainInbox" -> {
                    val limit = (call.argument<Int>("limit") ?: 100).coerceIn(1, 500)
                    result.success(drain(limit))
                }
                "ackInbox" -> {
                    val batchId = call.argument<String>("batchId") ?: return result.error("bad_args", "batchId missing", null)
                    db.ackBatch(batchId)
                    result.success(true)
                }
                "getDiagnostics" -> result.success(diagnostics())
                "smsPermissionState" -> result.success(if (smsPermission(context)) "granted" else "denied")
                "requestSmsPermission" -> {
                    val activity = activityProvider()
                    if (activity == null) result.success(false) else {
                        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.RECEIVE_SMS), 2001)
                        result.success(true)
                    }
                }
                "micPermissionState" -> result.success(
                    if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) "granted" else "denied"
                )
                "requestMicPermission" -> {
                    val activity = activityProvider()
                    if (activity == null) result.success(false) else {
                        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.RECORD_AUDIO), 2003)
                        result.success(true)
                    }
                }
                "notificationPermissionState" -> result.success(if (notificationsPermission(context)) "granted" else "denied")
                "requestNotificationPermission" -> requestNotifications(result)
                "canScheduleExactAlarms" -> result.success(exactAlarmAllowed(context))
                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        openIntent(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}")))
                    } else {
                        openIntent(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")))
                    }
                    result.success(true)
                }
                "openAppDetails" -> {
                    openIntent(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")))
                    result.success(true)
                }
                "openNotificationSettings" -> {
                    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    openIntent(intent)
                    result.success(true)
                }
                "openBatterySettings" -> {
                    openIntent(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    result.success(true)
                }
                "consumePendingRoute" -> {
                    val prefs = context.getSharedPreferences(Contract.PREFS, Context.MODE_PRIVATE)
                    val route = prefs.getString(Contract.PREF_PENDING_ROUTE, null)
                    prefs.edit().remove(Contract.PREF_PENDING_ROUTE).apply()
                    result.success(route)
                }
                "restoreAlarms" -> {
                    val scheduler = AlarmScheduler(context)
                    scheduler.rolloverCatchUp()
                    scheduler.restoreAll()
                    scheduler.scheduleRollover()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: NativeDbUnavailableException) {
            result.error("db_unavailable", e.message, null)
        } catch (e: Exception) {
            result.error("native_error", e.javaClass.simpleName, null)
        }
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val activity = activityProvider()
            if (activity == null) return result.success(false)
            ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2002)
        } else {
            openIntent(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
        }
        result.success(true)
    }

    private fun openIntent(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            // settings screen unavailable on this OEM: keep the app responsive
        }
    }

    private fun upsertAlarm(json: String): Boolean {
        val o = JSONObject(json)
        val uid = o.getString("occurrenceUid")
        val reminderId = o.getString("reminderId")
        val rev = o.optLong("rev", 1)
        val title = o.optString("title", "یادآور")
        val scheduledFor = o.getLong("scheduledFor")
        val followupCount = o.optInt("followupCount", 2)
        val interval = o.optInt("followupIntervalMin", 15)
        val priority = o.optInt("priority", 1)
        val stored = db.upsertAlarm(uid, reminderId, rev, title, scheduledFor, followupCount, interval, priority)
        if (stored) {
            AlarmScheduler(context).schedule(uid, reminderId, rev, title, scheduledFor, 0, followupCount, interval, priority)
        }
        return stored
    }

    private fun drain(limit: Int): String {
        val batch = db.drainEvents(limit)
        fun toArray(rows: List<Map<String, Any?>>): JSONArray {
            val arr = JSONArray()
            for (row in rows) {
                val obj = JSONObject()
                for ((k, v) in row) {
                    if (v == null) obj.put(k, JSONObject.NULL) else obj.put(k, v)
                }
                arr.put(obj)
            }
            return arr
        }
        return JSONObject().apply {
            put("batchId", batch.batchId)
            put("contractVersion", Contract.VERSION)
            put("sms", toArray(batch.sms))
            put("transactions", toArray(batch.transactions))
            put("resolutions", toArray(batch.resolutions))
            put("outcomes", toArray(batch.outcomes))
            put("occurrences", toArray(batch.occurrences))
        }.toString().also {
            db.logEvent(DiagCodes.IMPORT_DRAIN,
                "sms:${batch.sms.size},tx:${batch.transactions.size},res:${batch.resolutions.size},out:${batch.outcomes.size}")
        }
    }

    private fun diagnostics(): String {
        val key = KeyStoreManager(context)
        val native: Map<String, Any?> = try {
            db.open()
            db.diagnostics()
        } catch (e: Exception) {
            mapOf("nativeDbOpen" to false, "error" to e.javaClass.simpleName)
        }
        val receiverEnabled = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getReceiverInfo(ComponentName(context, SmsReceiver::class.java), PackageManager.ComponentInfoFlags.of(0)).enabled
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getReceiverInfo(ComponentName(context, SmsReceiver::class.java), 0).enabled
            }
        } catch (e: Exception) {
            false
        }
        val obj = JSONObject()
        obj.put("contractVersion", Contract.VERSION)
        obj.put("keyState", key.state())
        obj.put("smsPermission", if (smsPermission(context)) "granted" else "denied")
        obj.put("notificationPermission", if (notificationsPermission(context)) "granted" else "denied")
        obj.put("notificationChannelTx", NotificationChannels.channelState(context, NotificationChannels.TX))
        obj.put("notificationChannelReminder", NotificationChannels.channelState(context, NotificationChannels.REMINDER))
        obj.put("exactAlarmAllowed", exactAlarmAllowed(context))
        obj.put("receiverEnabled", receiverEnabled)
        val nativeJson = JSONObject()
        for ((k, v) in native) {
            when (v) {
                null -> nativeJson.put(k, JSONObject.NULL)
                is Map<*, *> -> {
                    val nested = JSONObject()
                    for ((nk, nv) in v) nested.put(nk.toString(), nv)
                    nativeJson.put(k, nested)
                }
                is List<*> -> {
                    val arr = JSONArray()
                    for (item in v) {
                        if (item is Map<*, *>) {
                            val nested = JSONObject()
                            for ((nk, nv) in item) nested.put(nk.toString(), nv)
                            arr.put(nested)
                        } else {
                            arr.put(item)
                        }
                    }
                    nativeJson.put(k, arr)
                }
                else -> nativeJson.put(k, v)
            }
        }
        obj.put("native", nativeJson)
        return obj.toString()
    }
}

/** Keeps the engine callback channel so live events can be pushed while Flutter is running. */
object BridgeEvents {
    private var channel: MethodChannel? = null

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    fun pushRoute(route: String) {
        try {
            channel?.invokeMethod("route", route)
        } catch (e: Exception) {
            // engine detached
        }
    }
}
