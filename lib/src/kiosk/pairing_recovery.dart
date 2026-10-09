// Adapted from the Visitor Connect tablet app (lib/pairing_recovery.dart).
// The kiosk keeps no outbox, so recovery only has to let in-flight work
// settle and then forget the pairing.
import 'dart:async';

/// The tablet routes that prove the tablet's own identity. A 401
/// KIOSK_NOT_PAIRED from one of them means this pairing is gone.
bool isRejectedTabletSession({
  required String path,
  required int statusCode,
  required bool hasTabletSession,
  required String? code,
}) {
  const routes = {
    '/kiosk/api/heartbeat.php',
    '/kiosk/api/admin-pin.php',
    '/kiosk/api/sign-in.php',
  };
  return hasTabletSession &&
      statusCode == 401 &&
      routes.contains(path) &&
      code == 'KIOSK_NOT_PAIRED';
}

class PairingRecoveryFailure implements Exception {
  const PairingRecoveryFailure(this.message);
  final String message;
}

class PairingRecovery {
  PairingRecovery({
    required this.drain,
    required this.clearLocalPairing,
    this.timeout = const Duration(seconds: 10),
  });

  final Future<void> Function() drain;
  final Future<void> Function() clearLocalPairing;
  final Duration timeout;
  Future<void>? _pending;

  Future<void> recover() async {
    try {
      await (_pending ??= _run()).timeout(timeout);
    } on TimeoutException {
      _pending = null;
      throw const PairingRecoveryFailure(
        'This tablet is still finishing its last request. Keep the app open '
        'and try again.',
      );
    }
  }

  Future<void> _run() async {
    try {
      await Future<void>.sync(drain);
      try {
        await clearLocalPairing();
      } catch (_) {
        throw const PairingRecoveryFailure(
          'Could not finish removing the old pairing. Keep the app open and '
          'try again.',
        );
      }
    } catch (_) {
      _pending = null;
      rethrow;
    }
  }
}
