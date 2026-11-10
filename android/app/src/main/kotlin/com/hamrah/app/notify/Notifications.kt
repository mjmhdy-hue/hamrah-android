package com.hamrah.app.notify

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.hamrah.app.Contract
import com.hamrah.app.DiagCodes
import com.hamrah.app.MainActivity
import com.hamrah.app.R
import com.hamrah.app.db.NativeInboxDb
import com.hamrah.app.sms.NativeSnapshot
import com.hamrah.app.util.PersianFormat

object NotificationChannels {
    const val TX = "hamrah_tx_v1"
    const val REMINDER = "hamrah_reminders_v1"

    fun ensure(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(TX, context.getString(R.string.channel_tx_name), NotificationManager.IMPORTANCE_HIGH).apply {
                description = context.getString(R.string.channel_tx_desc)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                enableVibration(true)
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(REMINDER, context.getString(R.string.channel_reminder_name), NotificationManager.IMPORTANCE_HIGH).apply {
                description = context.getString(R.string.channel_reminder_desc)
                enableVibration(true)
            }
        )
    }

    fun channelState(context: Context, id: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "legacy"
        val manager = context.getSystemService(NotificationManager::class.java) ?: return "missing"
        val channel = manager.getNotificationChannel(id) ?: return "missing"
        return when (channel.importance) {
            NotificationManager.IMPORTANCE_NONE -> "blocked"
            else -> "ok"
        }
    }
}

class TxNotifier(private val context: Context) {

    private val db = NativeInboxDb(context)

    fun canNotify(): Boolean {
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else true
        return granted && NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    fun notifyTx(
        txUid: String,
        direction: String,
        amountRial: Long,
        label: String,
        detail: String?,
        suggestions: List<NativeSnapshot.Category>,
        snapshot: NativeSnapshot
    ) {
        if (!canNotify()) {
            db.logEvent(DiagCodes.TX_NOTIFIED, "skipped_no_permission")
            return
        }
        NotificationChannels.ensure(context)
        val isIncome = direction == "in"
        val amountText = if (snapshot.hideAmounts) "مبلغ پنهان است" else PersianFormat.money(amountRial, snapshot.displayUnit)
        val title = if (snapshot.hideAmounts) {
            if (isIncome) "واریز جدید" else "برداشت جدید"
        } else {
            (if (isIncome) "واریز " else "برداشت ") + amountText
        }
        val lines = ArrayList<String>(2)
        detail?.takeIf { it.isNotBlank() }?.let { lines.add(it) }
        lines.add(label)
        val text = lines.joinToString(" • ")

        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = android.net.Uri.parse("hamrah://quick/$txUid")
            putExtra("route", "/quick?tx=$txUid")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPending = PendingIntent.getActivity(
            context, txUid.hashCode(), openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, NotificationChannels.TX)
            .setSmallIcon(R.drawable.ic_stat_hamrah)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setContentIntent(openPending)
            .setWhen(System.currentTimeMillis())

        suggestions.getOrNull(0)?.let { category ->
            builder.addAction(0, category.nameFa, categoryIntent(txUid, category.id, category.nameFa))
        }
        suggestions.getOrNull(1)?.let { category ->
            builder.addAction(0, category.nameFa, categoryIntent(txUid, category.id, category.nameFa))
        }
        builder.addAction(0, "بعداً", laterIntent(txUid))

        val publicVersion = NotificationCompat.Builder(context, NotificationChannels.TX)
            .setSmallIcon(R.drawable.ic_stat_hamrah)
            .setContentTitle("تراکنش جدید")
            .setContentText(context.getString(R.string.amount_hidden))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
        builder.setPublicVersion(publicVersion)

        NotificationManagerCompat.from(context).notify(txUid.hashCode(), builder.build())
        db.logEvent(DiagCodes.TX_NOTIFIED, txUid.take(8))
    }

    private fun categoryIntent(txUid: String, categoryId: String, categoryName: String): PendingIntent {
        val intent = Intent(context, TxActionReceiver::class.java).apply {
            action = TxActionReceiver.ACTION_CATEGORIZE
            putExtra("txUid", txUid)
            putExtra("categoryId", categoryId)
            putExtra("categoryName", categoryName)
        }
        return PendingIntent.getBroadcast(
            context, (txUid + categoryId).hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun laterIntent(txUid: String): PendingIntent {
        val intent = Intent(context, TxActionReceiver::class.java).apply {
            action = TxActionReceiver.ACTION_LATER
            putExtra("txUid", txUid)
        }
        return PendingIntent.getBroadcast(
            context, (txUid + "later").hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}

/** Notification actions that must work with no Flutter engine alive. */
class TxActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_CATEGORIZE = "com.hamrah.app.action.CATEGORIZE"
        const val ACTION_LATER = "com.hamrah.app.action.LATER"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val txUid = intent.getStringExtra("txUid") ?: return
        val db = NativeInboxDb(context)
        val pending = goAsync()
        try {
            when (intent.action) {
                ACTION_CATEGORIZE -> {
                    val categoryId = intent.getStringExtra("categoryId")
                    db.insertResolution(txUid, "categorize", categoryId, null)
                    db.logEvent(DiagCodes.TX_RESOLUTION, "categorize:${categoryId?.take(8)}")
                }
                ACTION_LATER -> {
                    db.insertResolution(txUid, "later", null, null)
                    db.logEvent(DiagCodes.TX_RESOLUTION, "later")
                }
            }
            NotificationManagerCompat.from(context).cancel(txUid.hashCode())
        } finally {
            pending.finish()
        }
    }
}
