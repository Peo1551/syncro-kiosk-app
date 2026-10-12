package com.syncroconnect.kiosk

import android.app.admin.DeviceAdminReceiver

/**
 * Device admin component for dedicated (device owner) kiosk tablets. Set up with
 *   adb shell dpm set-device-owner com.syncroconnect.kiosk/.KioskAdminReceiver
 * All lock-down work is done by MainActivity; this class only has to exist.
 */
class KioskAdminReceiver : DeviceAdminReceiver()
