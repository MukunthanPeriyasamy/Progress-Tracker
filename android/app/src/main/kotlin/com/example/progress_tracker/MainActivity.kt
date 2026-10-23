package com.example.progress_tracker

import android.content.pm.ApplicationInfo
import android.content.ComponentName
import android.content.Intent
import android.app.NotificationManager
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityManager
import android.provider.Settings
import android.net.Uri
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val preferences by lazy { getSharedPreferences("focus_flow", MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "focus_flow/apps")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permissions" -> {
                        val accessibility = getSystemService(AccessibilityManager::class.java)
                            .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                            .any { ComponentName(it.resolveInfo.serviceInfo.packageName, it.resolveInfo.serviceInfo.name) == ComponentName(this, FocusAccessibilityService::class.java) }
                        val component = ComponentName(this, FocusNotificationService::class.java)
                        val notifications = if (Build.VERSION.SDK_INT >= 27) {
                            getSystemService(NotificationManager::class.java).isNotificationListenerAccessGranted(component)
                        } else {
                            Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                                ?.split(':')?.any { ComponentName.unflattenFromString(it) == component } == true
                        }
                        result.success(mapOf("accessibility" to accessibility,
                            "notifications" to notifications, "overlay" to Settings.canDrawOverlays(this)))
                    }
                    "openSettings" -> {
                        val target = call.argument<String>("target")
                        val intent = when (target) {
                            "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            "notifications" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                            "overlay" -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                            "appNotifications" -> {
                                val pkg = call.argument<String>("package")
                                if (pkg.isNullOrBlank()) {
                                    result.error("INVALID_ARGUMENT", "Package required", null)
                                    return@setMethodCallHandler
                                }
                                if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                                else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
                            }
                            else -> null
                        }
                        if (intent == null) result.error("INVALID_ARGUMENT", "Unknown settings target", null)
                        else try { startActivity(intent); result.success(null) }
                        catch (error: Exception) { result.error("SETTINGS_UNAVAILABLE", "Settings could not be opened", null) }
                    }
                    "preferences" -> result.success(mapOf(
                        "consent" to preferences.getBoolean("consent", false),
                        "selected" to preferences.getStringSet("selected", emptySet())!!.toList()
                    ))
                    "consent" -> {
                        if (preferences.edit().putBoolean("consent", true).commit()) result.success(null)
                        else result.error("SAVE_FAILED", "Could not save consent", null)
                    }
                    "save" -> {
                        val selected = (call.arguments as? List<*>)?.filterIsInstance<String>()
                        val policy = FocusPolicy(this)
                        val protected = policy.protectedPackages()
                        val current = preferences.getStringSet("selected", emptySet())!!.toSet() - protected
                        if (selected == null) result.error("INVALID_ARGUMENT", "Expected package names", null)
                        else if (policy.active() && !selected.containsAll(current)) {
                            result.error("CYCLE_LOCKED", "Selected apps stay blocked until Sunday at 8 PM", null)
                        }
                        else if (preferences.edit().putStringSet("selected", selected.toSet() - protected).commit()) result.success(null)
                        else result.error("SAVE_FAILED", "Could not save selection", null)
                    }
                    "apps" -> {
                        if (!preferences.getBoolean("consent", false)) {
                            result.error("CONSENT_REQUIRED", "Allow access before listing apps", null)
                        } else worker.execute {
                            try {
                                val pm = packageManager
                                val protectedPackages = FocusPolicy(this).protectedPackages()
                                val installed = if (Build.VERSION.SDK_INT >= 33) {
                                    pm.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0))
                                } else {
                                    @Suppress("DEPRECATION")
                                    pm.getInstalledApplications(0)
                                }
                                val apps = installed.filter { it.packageName != packageName }
                                    .map { app ->
                                        val label = runCatching { app.loadLabel(pm).toString() }.getOrDefault(app.packageName)
                                        val icon = runCatching {
                                            val drawable = app.loadIcon(pm)
                                            val bitmap = Bitmap.createBitmap(72, 72, Bitmap.Config.ARGB_8888)
                                            drawable.setBounds(0, 0, 72, 72)
                                            drawable.draw(Canvas(bitmap))
                                            val output = ByteArrayOutputStream()
                                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                                            bitmap.recycle()
                                            output.toByteArray()
                                        }.getOrNull()
                                        mapOf(
                                            "package" to app.packageName,
                                            "name" to label,
                                            "icon" to icon,
                                            "system" to ((app.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                                            "protected" to (app.packageName in protectedPackages)
                                        )
                                    }.sortedBy { (it["name"] as String).lowercase() }
                                runOnUiThread { result.success(apps) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("APP_LIST_FAILED", "Could not read installed apps", null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }
}

