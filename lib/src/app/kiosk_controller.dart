import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../core/http/api_client.dart';
import '../core/session.dart';
import '../kiosk/card_reader.dart';
import '../kiosk/idle_countdown.dart';
import '../kiosk/kiosk_api.dart';
import '../kiosk/pairing_flow.dart';
import '../kiosk/pairing_recovery.dart';
import '../kiosk/tablet.dart';
import '../kiosk/tablet_store.dart';

enum KioskMode {
  boot,
  pair,
  recovery,
  wake,
  signIn,
  adminPin,
  admin,
  signedIn,
  signedOut,
  unlicensed,
}

/// The kiosk's state machine: pairing, the wake screen, one employee signed
/// in at a time, idle sign-out and the protected settings.
class KioskController extends ChangeNotifier {
  KioskController({
    required this.client,
    required this.store,
    this.appVersion = '',
    Future<void> Function()? prepareKiosk,
    this.signedOutHold = const Duration(seconds: 3),
  }) : api = KioskApi(client),
       _prepareKiosk = prepareKiosk ?? (() async {}) {
    idle = IdleCountdown(onExpired: _onIdleExpired);
    cardReader = CardReaderBuffer(
      onCard: (card) => unawaited(_onCard(card)),
      isListening: () =>
          !_disposed &&
          pairing != null &&
          !signingIn &&
          (mode == KioskMode.wake || mode == KioskMode.signIn),
    );
    client.onSessionEnded = (cookie, error) {
      if (session?.cookieHeader == cookie) {
        unawaited(signOut(message: error.message, ended: true));
      }
    };
  }

  final ApiClient client;
  final KioskApi api;
  final TabletStore store;
  final String appVersion;
  final Duration signedOutHold;
  final Future<void> Function() _prepareKiosk;

  late final IdleCountdown idle;
  late final CardReaderBuffer cardReader;

  KioskMode mode = KioskMode.boot;
  TabletPairing? pairing;
  AppSession? session;

  /// Bumped at every sign-in so screens can tell sessions apart.
  int sessionGeneration = 0;

  String? unlicensedMessage;
  String? recoveryMessage;
  String? signedOutMessage;

  bool signingIn = false;
  String? signInError;
  DateTime? signInBlockedUntil;

  Timer? _heartbeatTimer;
  Timer? _signedOutTimer;
  PairingFlow<PairResult>? _pairingFlow;
  PairingRecovery? _recovery;
  bool _disposed = false;

  TabletInfo get tablet => pairing?.tablet ?? const TabletInfo();

  int get tabletIdleSeconds {
    final seconds = tablet.idleSeconds;
    return seconds > 0 ? seconds : AppConfig.defaultIdleSeconds;
  }

  void _set(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  // ---------------------------------------------------------------- start

  Future<void> start() async {
    TabletPairing? saved;
    try {
      saved = await store.readPairing();
    } catch (_) {
      saved = null;
    }
    if (saved == null) {
      _set(() => mode = KioskMode.pair);
      return;
    }
    pairing = saved;
    client.kioskToken = saved.accessToken;
    _set(() => mode = KioskMode.wake);
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    unawaited(heartbeat());
    _heartbeatTimer = Timer.periodic(
      AppConfig.heartbeatInterval,
      (_) => unawaited(heartbeat()),
    );
  }

  // ---------------------------------------------------------------- pairing

  PairingFlow<PairResult> _flow() {
    return _pairingFlow ??= PairingFlow<PairResult>(
      prepareKiosk: _prepareKiosk,
      readTabletUuid: store.getOrCreateTabletUuid,
      pair: (code, uuid) => api.pair(
        pairingCode: code,
        tabletUuid: uuid,
        appVersion: appVersion,
      ),
      saveSession: (result) async {
        final uuid = await store.getOrCreateTabletUuid();
        await store.savePairing(
          TabletPairing(
            accessToken: result.accessToken,
            tabletUuid: uuid,
            tablet: result.tablet,
          ),
        );
      },
    );
  }

  /// Throws [PairingFailure] (shown on the pair screen) when it cannot pair.
  Future<void> pair(String code) async {
    final result = await _flow().run(code);
    final uuid = await store.getOrCreateTabletUuid();
    _pairingFlow = null;
    pairing = TabletPairing(
      accessToken: result.accessToken,
      tabletUuid: uuid,
      tablet: result.tablet,
    );
    client.kioskToken = result.accessToken;
    unlicensedMessage = null;
    _set(() => mode = KioskMode.wake);
    _startHeartbeat();
  }

  // ---------------------------------------------------------------- heartbeat

  Future<void> heartbeat() async {
    if (pairing == null) return;
    try {
      final info = await api.heartbeat(appVersion: appVersion);
      final current = pairing;
      if (current == null) return;
      pairing = current.withTablet(info);
      unawaited(store.savePairing(pairing!).catchError((Object _) {}));
      if (mode == KioskMode.unlicensed) {
        unlicensedMessage = null;
        _set(() => mode = KioskMode.wake);
      } else {
        _set(() {});
      }
    } on ApiException catch (e) {
      await _handleTabletError(e);
    } catch (_) {
      // Offline: keep going; the next heartbeat tries again.
    }
  }

  /// Returns true when the error was a tablet-level one and was handled.
  Future<bool> _handleTabletError(ApiException e) async {
    if (e.isNotPaired && e.statusCode == 401) {
      await _forgetPairing();
      return true;
    }
    if (e.isUnlicensed) {
      if (session != null) {
        await signOut(silent: true);
      }
      idle.stop();
      _signedOutTimer?.cancel();
      _set(() {
        unlicensedMessage = 'Syncro Kiosk is not active for this company';
        mode = KioskMode.unlicensed;
      });
      return true;
    }
    return false;
  }

  Future<void> _forgetPairing() async {
    if (session != null) await signOut(silent: true);
    idle.stop();
    _heartbeatTimer?.cancel();
    _signedOutTimer?.cancel();
    _recovery ??= PairingRecovery(
      drain: () async {},
      clearLocalPairing: () async {
        await store.clearPairing();
        pairing = null;
        client.kioskToken = null;
      },
    );
    try {
      await _recovery!.recover();
      _recovery = null;
      recoveryMessage = null;
      _set(() => mode = KioskMode.pair);
    } on PairingRecoveryFailure catch (e) {
      _set(() {
        recoveryMessage = e.message;
        mode = KioskMode.recovery;
      });
    }
  }

  Future<void> retryRecovery() => _forgetPairing();

  // ---------------------------------------------------------------- navigation

  void goWake() {
    idle.stop();
    _signedOutTimer?.cancel();
    cardReader.clear();
    _set(() {
      signInError = null;
      mode = pairing == null ? KioskMode.pair : KioskMode.wake;
    });
  }

  void openSignIn() {
    if (pairing == null) return;
    idle.start(tabletIdleSeconds);
    _set(() {
      signInError = null;
      mode = KioskMode.signIn;
    });
  }

  /// Any touch or key on a timed screen.
  void touch() {
    if (idle.isRunning) idle.reset();
  }

  void _onIdleExpired() {
    if (mode == KioskMode.signedIn) {
      unawaited(
        signOut(message: 'You were signed out because the kiosk was left idle.'),
      );
    } else if (mode == KioskMode.signIn ||
        mode == KioskMode.adminPin ||
        mode == KioskMode.admin) {
      goWake();
    }
  }

  // ---------------------------------------------------------------- sign in

  Future<void> _onCard(String card) async {
    if (mode == KioskMode.wake) openSignIn();
    await signInWithCard(card);
  }

  Future<void> signInWithCard(String card) =>
      _signIn(() => api.signInWithCard(card));

  Future<void> signInWithPin({
    required String clockNumber,
    required String pin,
  }) => _signIn(
    () => api.signInWithPin(clockNumber: clockNumber, pin: pin),
  );

  bool get signInBlocked {
    final until = signInBlockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  Future<void> _signIn(Future<AppSession> Function() request) async {
    if (signingIn || pairing == null) return;
    _set(() {
      signingIn = true;
      signInError = null;
    });
    try {
      final next = await request();
      if (_disposed) return;
      sessionGeneration++;
      session = next;
      signInBlockedUntil = null;
      signedOutMessage = null;
      idle.start(next.idleSeconds);
      _set(() {
        signingIn = false;
        mode = KioskMode.signedIn;
      });
    } on ApiException catch (e) {
      if (await _handleTabletError(e)) {
        signingIn = false;
        return;
      }
      _set(() {
        signingIn = false;
        if (e.isThrottled) {
          final wait = e.retryAfterSeconds ?? 30;
          signInBlockedUntil = DateTime.now().add(Duration(seconds: wait));
          signInError = throttleMessage(e.retryAfterSeconds);
        } else if (e.isNetwork) {
          signInError =
              'Cannot reach Syncro Connect. Check the tablet is online and try again.';
        } else {
          signInError = e.message;
        }
      });
      if (mode == KioskMode.signIn) idle.reset();
    } catch (_) {
      _set(() {
        signingIn = false;
        signInError = 'Sign-in could not finish. Please try again.';
      });
    }
  }

  /// The signed-in employee could not be set up (e.g. their account has no
  /// app access): end the session and show why on the sign-in screen.
  void abortSignIn(String message) {
    final current = session;
    if (current == null) return;
    _dropSession(current);
    idle.start(tabletIdleSeconds);
    _set(() {
      signInError = message;
      mode = KioskMode.signIn;
    });
  }

  void _dropSession(AppSession current) {
    session = null;
    client.endSession(current.cookieHeader);
    unawaited(api.signOut(current.cookieHeader));
  }

  /// Always clears the session locally and tells the server (fire and
  /// forget), then shows "You're signed out" before returning to wake.
  Future<void> signOut({
    String? message,
    bool ended = false,
    bool silent = false,
  }) async {
    final current = session;
    if (current != null) _dropSession(current);
    idle.stop();
    if (silent) return;
    _signedOutTimer?.cancel();
    _set(() {
      signedOutMessage = message;
      mode = KioskMode.signedOut;
    });
    _signedOutTimer = Timer(signedOutHold, () {
      if (mode == KioskMode.signedOut) goWake();
    });
  }

  /// The app was sent to the background: nobody stays signed in.
  void onAppPaused() {
    if (session != null) unawaited(signOut());
  }

  // ---------------------------------------------------------------- admin

  void openAdminPin() {
    if (pairing == null) return;
    idle.start(tabletIdleSeconds);
    _set(() => mode = KioskMode.adminPin);
  }

  /// Null when the PIN is accepted, otherwise the message to show.
  Future<String?> checkAdminPin(String pin) async {
    try {
      await api.checkAdminPin(pin);
      idle.start(tabletIdleSeconds);
      _set(() => mode = KioskMode.admin);
      unawaited(heartbeat());
      return null;
    } on ApiException catch (e) {
      if (await _handleTabletError(e)) return null;
      if (e.isThrottled) return throttleMessage(e.retryAfterSeconds);
      if (e.isNetwork) return 'Cannot reach Syncro Connect. Try again.';
      return e.message;
    }
  }

  /// Unpairs with the admin PIN. Null when done.
  Future<String?> unpair(String pin) async {
    try {
      await api.unpair(pin);
    } on ApiException catch (e) {
      if (e.isNotPaired && e.statusCode == 401) {
        await _forgetPairing();
        return null;
      }
      if (e.isThrottled) return throttleMessage(e.retryAfterSeconds);
      if (e.isNetwork) return 'Cannot reach Syncro Connect. Try again.';
      return e.message;
    }
    await _forgetPairing();
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeatTimer?.cancel();
    _signedOutTimer?.cancel();
    cardReader.dispose();
    idle.dispose();
    super.dispose();
  }
}
