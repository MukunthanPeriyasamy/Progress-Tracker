package com.example.progress_tracker

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.TextView
import android.widget.Toast

class FocusAccessibilityService : AccessibilityService(), SharedPreferences.OnSharedPreferenceChangeListener {
    private lateinit var policy: FocusPolicy
    private val handler = Handler(Looper.getMainLooper())
    private var foreground: String? = null
    private var lastRedirect = 0L
    private var banner: TextView? = null
    private val check = object : Runnable {
        override fun run() {
            enforce()
            // Also handles a selected app already open when Monday's cycle starts.
            handler.postDelayed(this, 1000)
        }
    }

    override fun onServiceConnected() {
        policy = FocusPolicy(this)
        policy.preferences.registerOnSharedPreferenceChangeListener(this)
        handler.removeCallbacks(check)
        handler.post(check)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        foreground = event.packageName?.toString()
        if (::policy.isInitialized) enforce()
    }

    private fun enforce() {
        if (!policy.shouldBlock(foreground)) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastRedirect < 1000) return
        lastRedirect = now
        // Android has no public force-stop API for another app. Leave its UI.
        var redirected = performGlobalAction(GLOBAL_ACTION_HOME)
        if (!redirected) {
            redirected = runCatching {
                startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }.isSuccess
        }
        if (redirected) {
            foreground = null
            showNotice()
        }
    }

    private fun showNotice() {
        removeBanner()
        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "App paused during your focus week", Toast.LENGTH_SHORT).show()
            return
        }
        val view = TextView(this).apply {
            text = "FocusFlow · App paused until Sunday 8 PM"
            setTextColor(0xffffffff.toInt())
            setBackgroundColor(0xff004ac6.toInt())
            setPadding(32, 24, 32, 24)
        }
        @Suppress("DEPRECATION")
        val type = if (android.os.Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
        val params = WindowManager.LayoutParams(WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT).apply { gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL; y = 140 }
        runCatching {
            getSystemService(WindowManager::class.java).addView(view, params)
            banner = view
            handler.postDelayed({ removeBanner() }, 2200)
        }.onFailure { Toast.makeText(this, "App paused during your focus week", Toast.LENGTH_SHORT).show() }
    }

    private fun removeBanner() {
        banner?.let { runCatching { getSystemService(WindowManager::class.java).removeView(it) } }
        banner = null
    }

    override fun onSharedPreferenceChanged(prefs: SharedPreferences?, key: String?) { enforce() }
    override fun onInterrupt() { foreground = null; removeBanner() }
    override fun onDestroy() {
        if (::policy.isInitialized) policy.preferences.unregisterOnSharedPreferenceChangeListener(this)
        handler.removeCallbacksAndMessages(null)
        removeBanner()
        super.onDestroy()
    }
}
