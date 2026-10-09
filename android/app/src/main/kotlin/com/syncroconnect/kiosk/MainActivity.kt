package com.syncroconnect.kiosk

import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Same soft-kiosk approach as the Visitor Connect tablet: keep the screen on,
// hide system bars, and offer Android lock task (screen pinning, or automatic
// lock-down when the tablet is provisioned as a device owner).
class MainActivity : FlutterActivity() {
    private val channelName = "syncroconnect.com/syncro_kiosk"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applySoftKioskFlags()
    }

    override fun onResume() {
        super.onResume()
        applySoftKioskFlags()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(kioskStatus())
                "startLockTask" -> {
                    try {
                        applySoftKioskFlags()
                        startLockTask()
                        result.success(kioskStatus())
                    } catch (e: Exception) {
                        result.success(kioskStatus() + mapOf("error" to (e.message ?: "Lock task request failed.")))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun applySoftKioskFlags() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
            View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }

    private fun kioskStatus(): Map<String, Any> {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val devicePolicyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val lockTaskState = activityManager.lockTaskModeState
        val active = lockTaskState != ActivityManager.LOCK_TASK_MODE_NONE
        val permitted = try {
            devicePolicyManager.isLockTaskPermitted(packageName)
        } catch (_: Exception) {
            false
        }
        return mapOf(
            "lockTaskActive" to active,
            "lockTaskPermitted" to permitted,
            "lockTaskState" to lockTaskState
        )
    }
}
