// Copied from the Visitor Connect tablet app (KioskService in lib/main.dart).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class KioskStatus {
  const KioskStatus({
    this.softKioskActive = true,
    this.lockTaskAvailable = false,
    this.lockTaskActive = false,
    this.message = 'Soft kiosk active.',
  });

  final bool softKioskActive;
  final bool lockTaskAvailable;
  final bool lockTaskActive;
  final String message;
}

class KioskService {
  const KioskService._();

  static const MethodChannel _channel = MethodChannel(
    'syncroconnect.com/syncro_kiosk',
  );

  /// Landscape, full screen, screen kept on.
  static Future<void> applySoftKiosk() async {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await WakelockPlus.enable();
    } catch (_) {
      // A missing plugin (tests, unsupported platform) must not stop the app.
    }
  }

  static Future<KioskStatus> status() async {
    await applySoftKiosk();
    if (kIsWeb || !Platform.isAndroid) {
      return KioskStatus(
        message: !kIsWeb && Platform.isIOS
            ? 'Soft kiosk active. Use iPad Guided Access or MDM Single App Mode for full tablet lock-down.'
            : 'Soft kiosk active. OS lock task is Android-only.',
      );
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('status');
      final permitted = raw?['lockTaskPermitted'] == true;
      final active = raw?['lockTaskActive'] == true;
      return KioskStatus(
        lockTaskAvailable: true,
        lockTaskActive: active,
        message: active
            ? 'Android lock task is active.'
            : permitted
            ? 'Android lock task is available.'
            : 'Soft kiosk active. Use Android screen pinning for a stronger lock, or device-owner kiosk mode for automatic lock-down.',
      );
    } catch (_) {
      return const KioskStatus(
        message: 'Soft kiosk active. Android kiosk status unavailable.',
      );
    }
  }

  static Future<KioskStatus> startLockTask() async {
    await applySoftKiosk();
    if (kIsWeb || !Platform.isAndroid) return status();
    try {
      await _channel.invokeMethod<void>('startLockTask');
    } catch (_) {}
    return status();
  }
}
