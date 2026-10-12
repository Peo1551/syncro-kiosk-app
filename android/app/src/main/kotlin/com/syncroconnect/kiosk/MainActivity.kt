package com.syncroconnect.kiosk

import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Same soft-kiosk approach as the Visitor Connect tablet: keep the screen on,
// hide system bars, and offer Android lock task.
//
// Two levels of lock:
// - Normal tablet: the app pins itself (startLockTask) whenever it is on
//   screen, and if it is closed anyway it brings itself back after a moment
//   (needs "Display over other apps", which lets it start from the
//   background). The admin can also make it the home screen. Exit kiosk mode
//   (admin PIN) stops all of this until the admin returns to the kiosk or the
//   app is reopened after being closed.
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
        // does not re-lock while they are still there or using another app.
        // Cleared when the admin returns to the kiosk, or when the app is
        // reopened after it was closed (stopped) while suspended.
        private var kioskSuspended = false

        // The app was stopped while suspended: the next resume re-locks.
        private var stoppedWhileSuspended = false

        // Dart is running another app on purpose (the camera for a leave
        // photo). Until then (a safety limit), no reopen and no re-pin.
        private var externalUntil = 0L

        // Android settings opened from tablet settings; cleared when the kiosk
        // comes back. No reopen, no re-pin and no end of suspension for it,
        // up to a safety limit.
        private var settingsUntil = 0L

        // Tablet settings (admin screen) is showing: the periodic check does
        // not pin underneath the admin.
        private var adminOpen = false

        private const val prefsName = "syncro_kiosk_native"
        private const val prefHomeChosen = "ordinary_home_chosen"
        private const val returnDelayMs = 2000L
        private const val externalLimitMs = 10 * 60 * 1000L
        private const val settingsLimitMs = 5 * 60 * 1000L
    }

    private val dpm: DevicePolicyManager
        get() = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    private val adminComponent: ComponentName
        get() = ComponentName(this, KioskAdminReceiver::class.java)

    // A normal (not dedicated) tablet: Android always lets someone unpin with
    // the Back + Overview gesture, so the kiosk pins itself again whenever it
    // is on screen and not pinned. Only Exit kiosk mode (behind the admin PIN)
    // stops that, until the app next leaves the screen.
    private val repinHandler = Handler(Looper.getMainLooper())
    private val repinCheck = object : Runnable {
        override fun run() {
            if (!adminOpen) repinIfNeeded()
            repinHandler.postDelayed(this, 1500)
        }
    }

    // Android shows its own "App is pinned" message on every pin and waits for
    // Got it, so a pin is asked for once and then left alone for a while;
    // asking again every check made that message flash on and off.
    private var lastPinRequestAt = 0L

    private fun externalExpected(): Boolean =
        System.currentTimeMillis() < externalUntil

    private fun settingsOpen(): Boolean =
        System.currentTimeMillis() < settingsUntil

    // Another app is expected on screen (camera or Android settings).
    private fun holdingOpen(): Boolean = externalExpected() || settingsOpen()

    private fun repinIfNeeded(force: Boolean = false) {
        if (kioskSuspended || isDeviceOwner()) return
        if (holdingOpen()) return
        if (lockState() != "none") return
        val now = System.currentTimeMillis()
        // A forced request skips the long wait, but never asks twice within a
        // few seconds while Android is still showing its pinned message.
        if (now - lastPinRequestAt < (if (force) 3000 else 15000)) return
        lastPinRequestAt = now
        try {
            startLockTask()
        } catch (_: Exception) {
        }
    }

    private val homeAlias: ComponentName
        get() = ComponentName(packageName, "$packageName.KioskHomeAlias")

    // Normal tablet: if the kiosk is closed (Home, Recents, another app), bring
    // it back after a moment. Android only lets an app start itself from the
    // background when it holds "Display over other apps".
    private val returnHandler = Handler(Looper.getMainLooper())
    private val returnToKiosk = Runnable {
        if (kioskSuspended || isDeviceOwner() || holdingOpen()) {
            return@Runnable
        }
        if (!canReturn()) return@Runnable
        try {
            applicationContext.startActivity(
                Intent(applicationContext, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                )
            )
        } catch (_: Exception) {
        }
    }

    private fun canReturn(): Boolean = try {
        Settings.canDrawOverlays(this)
    } catch (_: Exception) {
        false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applySoftKioskFlags()
    }

    override fun onResume() {
        super.onResume()
        returnHandler.removeCallbacks(returnToKiosk)
        applySoftKioskFlags()
        val backFromSettings = settingsOpen()
        settingsUntil = 0L
        // Reopened after the admin's exit and leaving the app: lock again.
        if (stoppedWhileSuspended) {
            stoppedWhileSuspended = false
            kioskSuspended = false
        }
        if (isDeviceOwner()) {
            if (!kioskSuspended) {
                try {
                    enterDedicatedMode()
                } catch (_: Exception) {
                    // Never crash the kiosk over a lock-down failure.
                }
            }
        } else if (!backFromSettings) {
            // Pin straight away when coming back, not after the throttle.
            repinIfNeeded(force = true)
        }
        repinHandler.removeCallbacks(repinCheck)
        repinHandler.postDelayed(repinCheck, 1500)
    }

    override fun onPause() {
        repinHandler.removeCallbacks(repinCheck)
        super.onPause()
    }

    override fun onStop() {
        super.onStop()
        if (isChangingConfigurations) return
        if (kioskSuspended) {
            // The admin exited and then left the app: it re-locks when
            // reopened. Opening the camera or Android settings does not count.
            if (!holdingOpen()) stoppedWhileSuspended = true
            return
        }
        if (isDeviceOwner()) return
        // Camera or Android settings expected: come back only if they are
        // still open after their safety limit.
        val now = System.currentTimeMillis()
        val holdUntil = maxOf(externalUntil, settingsUntil)
        val delay = if (holdUntil > now) holdUntil - now + returnDelayMs else returnDelayMs
        returnHandler.removeCallbacks(returnToKiosk)
        returnHandler.postDelayed(returnToKiosk, delay)
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
                        kioskSuspended = false
                        stoppedWhileSuspended = false
                        if (isDeviceOwner()) {
                            enterDedicatedMode()
                        } else {
                            lastPinRequestAt = System.currentTimeMillis()
                            startLockTask()
                        }
                        result.success(kioskStatus())
                    }
                    "exitKioskMode" -> {
                        kioskSuspended = true
                        stoppedWhileSuspended = false
                        returnHandler.removeCallbacks(returnToKiosk)
                        if (isDeviceOwner()) {
                            exitDedicatedMode()
                        } else {
                            try {
                                stopLockTask()
                            } catch (_: Exception) {
                            }
                        }
                        result.success(kioskStatus())
                    }
                    "resumeKioskMode" -> {
                        kioskSuspended = false
                        stoppedWhileSuspended = false
                        adminOpen = false
                        if (isDeviceOwner()) {
                            enterDedicatedMode()
                        } else {
                            repinIfNeeded(force = true)
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
                    "setAdminOpen" -> {
                        adminOpen = call.argument<Boolean>("open") == true
                        if (!adminOpen) repinIfNeeded(force = true)
                        result.success(kioskStatus())
                    }
                    "beginExternalActivity" -> {
                        externalUntil = System.currentTimeMillis() + externalLimitMs
                        returnHandler.removeCallbacks(returnToKiosk)
                        // Screen pinning stops another app (the camera)
                        // opening, so unpin for it on a normal tablet. A
                        // dedicated tablet is left as it is.
                        if (call.argument<Boolean>("unpin") == true &&
                            !isDeviceOwner() && lockState() == "pinned"
                        ) {
                            try {
                                stopLockTask()
                            } catch (_: Exception) {
                            }
                        }
                        result.success(kioskStatus())
                    }
                    "endExternalActivity" -> {
                        externalUntil = 0L
                        if (!adminOpen) repinIfNeeded(force = true)
                        result.success(kioskStatus())
                    }
                    "openOverlaySettings" -> {
                        openSettings(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                        )
                        result.success(kioskStatus())
                    }
                    "setHomeApp" -> {
                        if (!isDeviceOwner()) {
                            val on = call.argument<Boolean>("enabled") == true
                            getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                                .edit().putBoolean(prefHomeChosen, on).apply()
                            packageManager.setComponentEnabledSetting(
                                homeAlias,
                                if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                PackageManager.DONT_KILL_APP
                            )
                            openSettings(Intent(Settings.ACTION_HOME_SETTINGS))
                        }
                        result.success(kioskStatus())
                    }
                    "isHomeApp" -> result.success(isHomeApp())
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.success(kioskStatus() + mapOf("error" to (e.message ?: "Kiosk request failed.")))
            }
        }
    }

    // Opens an Android settings screen for the admin. Pinning would block it,
    // so a normal tablet unpins first; nothing reopens or re-pins until the
    // kiosk is back on screen.
    private fun openSettings(intent: Intent) {
        settingsUntil = System.currentTimeMillis() + settingsLimitMs
        returnHandler.removeCallbacks(returnToKiosk)
        if (!isDeviceOwner() && lockState() == "pinned") {
            try {
                stopLockTask()
            } catch (_: Exception) {
            }
        }
        try {
            startActivity(intent)
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_SETTINGS))
            } catch (_: Exception) {
                settingsUntil = 0L
            }
        }
    }

    private fun isHomeApp(): Boolean = try {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        packageManager.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)
            ?.activityInfo?.packageName == packageName
    } catch (_: Exception) {
        false
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
        // Keep the home screen entry if the admin chose it on a normal tablet.
        val homeChosen = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getBoolean(prefHomeChosen, false)
        if (!homeChosen) {
            packageManager.setComponentEnabledSetting(
                homeAlias,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
        }
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
            "isDeviceOwner" to isDeviceOwner(),
            "suspended" to kioskSuspended,
            "canReturn" to canReturn(),
            "isHomeApp" to isHomeApp()
        )
    }
}
