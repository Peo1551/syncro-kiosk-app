package com.syncroconnect.kiosk

import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Same soft-kiosk approach as the Visitor Connect tablet: keep the screen on,
// hide system bars, and offer Android lock task.
//
// Two levels of lock:
// - Normal tablet: the admin can turn on screen pinning from tablet settings
//   (startLockTask). Nothing happens automatically.
// - Dedicated tablet (this app is the device owner): on every resume the app
//   enters full lock task mode with no Home, Recents, notifications or global
//   actions, disables the status bar and keyguard, and becomes the home
//   launcher so it comes back after a reboot. The admin can exit from tablet
//   settings; it re-locks when the app is next opened or the admin returns to
//   the kiosk.
class MainActivity : FlutterActivity() {
    private val channelName = "syncroconnect.com/syncro_kiosk"

    companion object {
        // Set when the admin exits kiosk mode from tablet settings, so the app
        // does not re-lock while they are still there. Cleared when the app
        // leaves the foreground or the admin returns to the kiosk.
        private var kioskSuspended = false
    }

    private val dpm: DevicePolicyManager
        get() = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    private val adminComponent: ComponentName
        get() = ComponentName(this, KioskAdminReceiver::class.java)

    private val homeAlias: ComponentName
        get() = ComponentName(packageName, "$packageName.KioskHomeAlias")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applySoftKioskFlags()
    }

    override fun onResume() {
        super.onResume()
        applySoftKioskFlags()
        if (isDeviceOwner() && !kioskSuspended) {
            try {
                enterDedicatedMode()
            } catch (_: Exception) {
                // Never crash the kiosk over a lock-down failure.
            }
        }
    }

    override fun onStop() {
        super.onStop()
        // Leaving the app ends an admin's exit; it re-locks when reopened.
        kioskSuspended = false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(kioskStatus())
                    "isDeviceOwner" -> result.success(isDeviceOwner())
                    "lockState" -> result.success(lockState())
                    "startLockTask" -> {
                        applySoftKioskFlags()
                        if (isDeviceOwner()) {
                            kioskSuspended = false
                            enterDedicatedMode()
                        } else {
                            startLockTask()
                        }
                        result.success(kioskStatus())
                    }
                    "exitKioskMode" -> {
                        if (isDeviceOwner()) {
                            kioskSuspended = true
                            exitDedicatedMode()
                        }
                        result.success(kioskStatus())
                    }
                    "resumeKioskMode" -> {
                        // Only re-locks a dedicated tablet; a normal tablet is
                        // left exactly as it is.
                        if (isDeviceOwner()) {
                            kioskSuspended = false
                            enterDedicatedMode()
                        }
                        result.success(kioskStatus())
                    }
                    "releaseDeviceOwner" -> {
                        if (isDeviceOwner()) {
                            kioskSuspended = true
                            exitDedicatedMode()
                            @Suppress("DEPRECATION")
                            dpm.clearDeviceOwnerApp(packageName)
                            try {
                                dpm.removeActiveAdmin(adminComponent)
                            } catch (_: Exception) {
                            }
                        }
                        result.success(kioskStatus())
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.success(kioskStatus() + mapOf("error" to (e.message ?: "Kiosk request failed.")))
            }
        }
    }

    private fun isDeviceOwner(): Boolean = try {
        dpm.isDeviceOwnerApp(packageName)
    } catch (_: Exception) {
        false
    }

    private fun enterDedicatedMode() {
        val admin = adminComponent
        dpm.setLockTaskPackages(admin, arrayOf(packageName))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // No Home, Recents, notifications, global actions or system info.
            dpm.setLockTaskFeatures(admin, DevicePolicyManager.LOCK_TASK_FEATURE_NONE)
        }
        dpm.setStatusBarDisabled(admin, true)
        dpm.setKeyguardDisabled(admin, true)
        packageManager.setComponentEnabledSetting(
            homeAlias,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )
        val home = IntentFilter(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            addCategory(Intent.CATEGORY_DEFAULT)
        }
        dpm.clearPackagePersistentPreferredActivities(admin, packageName)
        dpm.addPersistentPreferredActivity(admin, home, homeAlias)
        if (lockState() != "locked") startLockTask()
    }

    private fun exitDedicatedMode() {
        val admin = adminComponent
        try {
            stopLockTask()
        } catch (_: Exception) {
        }
        // Removing the package from the allow-list also ends lock task and
        // stops the activity re-entering it automatically (if_whitelisted).
        dpm.setLockTaskPackages(admin, arrayOf())
        dpm.setStatusBarDisabled(admin, false)
        dpm.setKeyguardDisabled(admin, false)
        dpm.clearPackagePersistentPreferredActivities(admin, packageName)
        packageManager.setComponentEnabledSetting(
            homeAlias,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP
        )
    }

    private fun lockState(): String {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return when (activityManager.lockTaskModeState) {
            ActivityManager.LOCK_TASK_MODE_LOCKED -> "locked"
            ActivityManager.LOCK_TASK_MODE_PINNED -> "pinned"
            else -> "none"
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
        val lockTaskState = activityManager.lockTaskModeState
        val active = lockTaskState != ActivityManager.LOCK_TASK_MODE_NONE
        val permitted = try {
            dpm.isLockTaskPermitted(packageName)
        } catch (_: Exception) {
            false
        }
        return mapOf(
            "lockTaskActive" to active,
            "lockTaskPermitted" to permitted,
            "lockTaskState" to lockTaskState,
            "lockState" to lockState(),
            "isDeviceOwner" to isDeviceOwner()
        )
    }
}
