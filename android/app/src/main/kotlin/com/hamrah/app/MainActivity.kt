package com.hamrah.app

import android.content.Intent
import android.os.Bundle
import com.hamrah.app.bridge.NativeBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var bridge: NativeBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NativeBridge.activityRef = this
        bridge = NativeBridge(this, flutterEngine.dartExecutor.binaryMessenger) { this }.also { it.register() }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        NativeBridge.activityRef = this
    }

    override fun onDestroy() {
        if (NativeBridge.activityRef === this) NativeBridge.activityRef = null
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NotificationChannelsCompat.ensure(this)
    }

    private fun handleIntent(intent: Intent?) {
        val route = intent?.getStringExtra("route")
            ?: intent?.data?.takeIf { it.scheme == "hamrah" && it.host == "quick" }?.lastPathSegment?.let { "/quick?tx=$it" }
            ?: return
        val prefs = getSharedPreferences(Contract.PREFS, MODE_PRIVATE)
        prefs.edit().putString(Contract.PREF_PENDING_ROUTE, route).apply()
        com.hamrah.app.bridge.BridgeEvents.pushRoute(route)
        intent?.removeExtra("route")
    }
}

private object NotificationChannelsCompat {
    fun ensure(activity: MainActivity) {
        com.hamrah.app.notify.NotificationChannels.ensure(activity)
    }
}
