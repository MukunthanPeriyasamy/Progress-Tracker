package com.example.progress_tracker

import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class FocusNotificationService : NotificationListenerService(), SharedPreferences.OnSharedPreferenceChangeListener {
    private lateinit var policy: FocusPolicy
    private val handler = Handler(Looper.getMainLooper())
    private var connected = false
    private val sweep = object : Runnable {
        override fun run() {
            clearSelected()
            handler.postDelayed(this, 60_000 - System.currentTimeMillis() % 60_000)
        }
    }

    override fun onListenerConnected() {
        policy = FocusPolicy(this)
        connected = true
        policy.preferences.registerOnSharedPreferenceChangeListener(this)
        handler.removeCallbacks(sweep)
        handler.post(sweep)
    }

    override fun onNotificationPosted(notification: StatusBarNotification?) {
        if (connected && policy.shouldBlock(notification?.packageName)) {
            notification?.let { runCatching { cancelNotification(it.key) } }
        }
    }

    private fun clearSelected() {
        if (!connected || !policy.active()) return
        runCatching { activeNotifications?.forEach { onNotificationPosted(it) } }
    }

    override fun onSharedPreferenceChanged(prefs: SharedPreferences?, key: String?) { clearSelected() }
    override fun onListenerDisconnected() { cleanup() }
    private fun cleanup() {
        connected = false
        handler.removeCallbacksAndMessages(null)
        if (::policy.isInitialized) policy.preferences.unregisterOnSharedPreferenceChangeListener(this)
    }
    override fun onDestroy() { cleanup(); super.onDestroy() }
}
