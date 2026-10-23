package com.example.progress_tracker

import android.content.Context
import android.content.Intent
import android.provider.Settings
import java.util.Calendar

/** Shared by both services in the app process, independent of Flutter. */
class FocusPolicy(private val context: Context) {
    val preferences = context.getSharedPreferences("focus_flow", Context.MODE_PRIVATE)

    fun active(now: Calendar = Calendar.getInstance()): Boolean {
        val day = now.get(Calendar.DAY_OF_WEEK)
        val hour = now.get(Calendar.HOUR_OF_DAY)
        return when (day) {
            Calendar.MONDAY -> hour >= 6
            Calendar.SUNDAY -> hour < 20
            else -> true
        }
    }

    fun protectedPackages(): Set<String> {
        val pm = context.packageManager
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        @Suppress("DEPRECATION")
        val launchers = pm.queryIntentActivities(home, 0).map { it.activityInfo.packageName }
        val settings = pm.resolveActivity(Intent(Settings.ACTION_SETTINGS), 0)?.activityInfo?.packageName
        val keyboard = Settings.Secure.getString(context.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)?.substringBefore('/')
        return setOfNotNull(context.packageName, "android", "com.android.systemui", "com.android.settings", settings, keyboard) + launchers
    }

    fun shouldBlock(packageName: String?): Boolean = packageName != null &&
        preferences.getBoolean("consent", false) && active() &&
        preferences.getStringSet("selected", emptySet())!!.contains(packageName) &&
        packageName !in protectedPackages()
}
