// Copied from the Visitor Connect tablet app (KioskService in lib/main.dart),
// extended with dedicated (device owner) kiosk mode on Android.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// How firmly Android is holding the tablet in this app.
enum KioskLockState {
  /// No OS lock: soft kiosk only (full screen, screen kept on).
  none,

  /// Screen pinning: the user could unpin with a button gesture.
  pinned,

  /// Full lock task on a dedicated tablet: no way out except tablet settings.
  locked;

  static KioskLockState parse(Object? raw) => switch (raw) {
    'locked' => KioskLockState.locked,
    'pinned' => KioskLockState.pinned,
    _ => KioskLockState.none,
  };

  /// Label shown in tablet settings.
  String get label => switch (this) {
    KioskLockState.locked => 'Locked (dedicated device)',
    KioskLockState.pinned => 'Screen pinning',
    KioskLockState.none => 'Off',
  };
}

class KioskStatus {
  const KioskStatus({
    this.softKioskActive = true,
    this.lockTaskAvailable = false,
    this.lockTaskActive = false,
    this.isDeviceOwner = false,
    this.lockState = KioskLockState.none,
    this.suspended = false,
    this.canReturn = false,
    this.isHomeApp = false,
    this.message = 'Soft kiosk active.',
  });

  static const exitedMessage =
      'Kiosk lock is off until you return to the kiosk or reopen the app.';
  static const dedicatedHint =
      'For a fully locked tablet, set it up as a dedicated kiosk (see setup guide).';

  /// Builds the status from the Android `status` reply.
  factory KioskStatus.fromAndroid(Map<String, dynamic>? raw) {
    final owner = raw?['isDeviceOwner'] == true;
    var state = KioskLockState.parse(raw?['lockState']);
    // Older replies only carried lockTaskActive.
    if (state == KioskLockState.none && raw?['lockTaskActive'] == true) {
      state = KioskLockState.pinned;
    }
    final active = state != KioskLockState.none;
    final suspended = raw?['suspended'] == true;
    final String message;
    if (owner) {
      message = state == KioskLockState.none
          ? 'Kiosk mode is paused. It locks again when you return to the kiosk.'
          : 'This tablet is a dedicated kiosk.';
    } else {
      message = suspended ? exitedMessage : dedicatedHint;
    }
    return KioskStatus(
      lockTaskAvailable: true,
      lockTaskActive: active,
      isDeviceOwner: owner,
      lockState: state,
      suspended: suspended,
      canReturn: raw?['canReturn'] == true,
      isHomeApp: raw?['isHomeApp'] == true,
      message: message,
    );
  }

  final bool softKioskActive;
  final bool lockTaskAvailable;
  final bool lockTaskActive;

  /// True when this app manages the tablet as a dedicated kiosk.
  final bool isDeviceOwner;
  final KioskLockState lockState;

  /// The admin used Exit kiosk mode and has not returned to the kiosk yet.
  final bool suspended;

  /// Normal tablet: the app may bring itself back if closed ("Display over
  /// other apps" is allowed).
  final bool canReturn;

  /// The app is the tablet's home screen.
  final bool isHomeApp;
  final String message;
}

class KioskService {
  const KioskService._();

  static const MethodChannel channel = MethodChannel(
    'syncroconnect.com/syncro_kiosk',
  );

  /// Whether to talk to the Android side. Tests switch this on.
  @visibleForTesting
  static bool Function() isAndroid = _platformIsAndroid;

  static bool _platformIsAndroid() => !kIsWeb && Platform.isAndroid;

  /// Landscape, full screen, screen kept on.
  static Future<void> applySoftKiosk() => softKiosk();

  /// The soft-kiosk step. Tests replace it, because the desktop wake lock
  /// plugin never answers inside a widget test.
  @visibleForTesting
  static Future<void> Function() softKiosk = _applySoftKiosk;

  static Future<void> _applySoftKiosk() async {
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
    if (!isAndroid()) {
      return KioskStatus(
        message: !kIsWeb && Platform.isIOS
            ? 'Soft kiosk active. Use iPad Guided Access or MDM Single App Mode for full tablet lock-down.'
            : 'Soft kiosk active. OS lock task is Android-only.',
      );
    }
    try {
      final raw = await channel.invokeMapMethod<String, dynamic>('status');
      return KioskStatus.fromAndroid(raw);
    } catch (_) {
      return const KioskStatus(
        message: 'Soft kiosk active. Android kiosk status unavailable.',
      );
    }
  }

  static Future<bool> isDeviceOwner() async {
    if (!isAndroid()) return false;
    try {
      return await channel.invokeMethod<bool>('isDeviceOwner') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<KioskLockState> lockState() async {
    if (!isAndroid()) return KioskLockState.none;
    try {
      return KioskLockState.parse(
        await channel.invokeMethod<String>('lockState'),
      );
    } catch (_) {
      return KioskLockState.none;
    }
  }

  /// Screen pinning on a normal tablet; full lock on a dedicated one.
  static Future<KioskStatus> startLockTask() => _call('startLockTask');

  /// Unlock until the admin returns to the kiosk or the app is reopened after
  /// being closed. A normal tablet also stops pinning and reopening itself.
  static Future<KioskStatus> exitKioskMode() => _call('exitKioskMode');

  /// Lock again after [exitKioskMode].
  static Future<KioskStatus> resumeKioskMode() => _call('resumeKioskMode');

  /// Tablet settings is showing (true) or closed (false). While it shows,
  /// the app does not pin itself underneath the admin.
  static Future<void> setAdminOpen(bool open) async {
    if (!isAndroid()) return;
    try {
      await channel.invokeMethod<void>('setAdminOpen', {'open': open});
    } catch (_) {}
  }

  /// Runs [body] while another app is expected on screen (the camera), so the
  /// kiosk neither reopens itself over it nor pins itself. With [unpin], a
  /// normal tablet is unpinned for it (pinning would block the other app) and
  /// pinned again afterwards.
  static Future<T> duringExternalActivity<T>(
    Future<T> Function() body, {
    bool unpin = false,
  }) async {
    await _invoke('beginExternalActivity', {'unpin': unpin});
    try {
      return await body();
    } finally {
      await _invoke('endExternalActivity');
    }
  }

  /// Normal tablet: opens Android's "Display over other apps" page for this
  /// app, so the kiosk can reopen itself if closed.
  static Future<KioskStatus> openReturnPermission() =>
      _call('openOverlaySettings');

  /// Normal tablet: offers the kiosk as the home screen (true) or stops
  /// offering it (false), then opens Android's home app choice.
  static Future<KioskStatus> setHomeApp(bool enabled) =>
      _call('setHomeApp', {'enabled': enabled});

  static Future<bool> isHomeApp() async {
    if (!isAndroid()) return false;
    try {
      return await channel.invokeMethod<bool>('isHomeApp') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _invoke(String method, [Object? arguments]) async {
    if (!isAndroid()) return;
    try {
      await channel.invokeMethod<void>(method, arguments);
    } catch (_) {}
  }

  /// Dedicated tablet only: unlock and stop managing the tablet for good.
  static Future<KioskStatus> releaseDeviceOwner() =>
      _call('releaseDeviceOwner');

  static Future<KioskStatus> _call(String method, [Object? arguments]) async {
    await applySoftKiosk();
    await _invoke(method, arguments);
    return status();
  }
}
