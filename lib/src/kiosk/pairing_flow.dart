// Copied from the Visitor Connect tablet app (lib/pairing_flow.dart).
import 'dart:async';

class PairingFailure implements Exception {
  const PairingFailure(this.message);
  final String message;
}

class PairingUncertain extends PairingFailure {
  const PairingUncertain()
    : super(
        'The pairing may have been accepted, but confirmation was lost. '
        'In Syncro Connect, check Settings › Syncro Kiosk and '
        'create a new pairing code before trying again.',
      );
}

/// Keeps pending storage operations and a received session across retries.
/// A timeout stops waiting; it cannot cancel a platform storage operation.
class PairingFlow<T extends Object> {
  PairingFlow({
    required this.prepareKiosk,
    required this.readTabletUuid,
    required this.pair,
    required this.saveSession,
    this.storageTimeout = const Duration(seconds: 10),
    this.kioskTimeout = const Duration(seconds: 2),
  });

  final Future<void> Function() prepareKiosk;
  final Future<String> Function() readTabletUuid;
  final Future<T> Function(String code, String uuid) pair;
  final Future<void> Function(T session) saveSession;
  final Duration storageTimeout;
  final Duration kioskTimeout;
  final Set<String> _uncertainCodes = {};
  Future<String>? _uuid;
  T? _session;
  Future<void>? _saving;
  Future<T>? _attempt;

  Future<T> run(String code) {
    return _attempt ??= _run(code).whenComplete(() => _attempt = null);
  }

  Future<String> _readUuid() async {
    try {
      return await readTabletUuid();
    } catch (_) {
      _uuid = null;
      rethrow;
    }
  }

  Future<void> _save(T session) async {
    try {
      await saveSession(session);
    } catch (_) {
      _saving = null;
      rethrow;
    }
  }

  Future<T> _run(String code) async {
    // Screen orientation/wake lock must not prevent device registration.
    try {
      await prepareKiosk().timeout(kioskTimeout);
    } catch (_) {
      // Protected settings still provide the separate kiosk status/controls.
    }
    if (_session == null) {
      // Once a session was received, saving it takes precedence over any code
      // currently displayed. Only a new provider request uses the input code.
      if (_uncertainCodes.contains(code)) throw const PairingUncertain();
      String uuid;
      try {
        uuid = await (_uuid ??= _readUuid()).timeout(storageTimeout);
      } catch (_) {
        throw const PairingFailure(
          'Cannot access secure storage on this tablet. Try Pair again. '
          'If this continues, restart the app and contact support.',
        );
      }
      try {
        _session = await pair(code, uuid);
      } on PairingUncertain {
        _uncertainCodes.add(code);
        rethrow;
      }
    }
    final session = _session!;
    try {
      await (_saving ??= _save(session)).timeout(storageTimeout);
    } catch (_) {
      throw const PairingFailure(
        'Pairing was accepted, but this tablet could not save it securely. '
        'Keep the app open and press Pair again to finish saving.',
      );
    }
    return session;
  }
}
