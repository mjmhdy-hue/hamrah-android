package com.hamrah.app

import android.app.Application
import android.util.Log
import com.hamrah.app.alarm.AlarmScheduler
import com.hamrah.app.crypto.KeyStoreManager
import com.hamrah.app.db.NativeInboxDb
import com.hamrah.app.notify.NotificationChannels
import com.hamrah.app.sms.SmsRecovery

class HamrahApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                NativeInboxDb(this).logEvent("crash", "uncaught:${error.javaClass.simpleName}")
            } catch (ignored: Exception) {
            }
            Log.e("HamrahApp", "uncaught", error)
        }
        try {
            System.loadLibrary("sqlcipher")
        } catch (e: Throwable) {
            Log.e("HamrahApp", "sqlcipher library load failed", e)
        }
        NotificationChannels.ensure(this)
        thread {
            try {
                val db = NativeInboxDb(this)
                db.open()
                db.logEvent(DiagCodes.DB_OPENED, "native_inbox")
            } catch (e: Exception) {
                Log.e("HamrahApp", "native db open failed", e)
                try {
                    NativeInboxDb(this).logEvent(DiagCodes.DB_OPEN_FAILED, e.javaClass.simpleName)
                } catch (ignored: Exception) {
                }
            }
            try {
                KeyStoreManager(this).state()
            } catch (e: Exception) {
                Log.e("HamrahApp", "key check failed", e)
            }
            try {
                val scheduler = AlarmScheduler(this)
                scheduler.rolloverCatchUp()
                scheduler.restoreAll()
                scheduler.scheduleRollover()
            } catch (e: Exception) {
                Log.e("HamrahApp", "alarm restore failed", e)
            }
            SmsRecovery.run(this)
        }
    }

    private fun thread(block: () -> Unit) {
        Thread(block, "hamrah-startup").start()
    }
}
