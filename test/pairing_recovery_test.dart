import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncro_kiosk/src/kiosk/pairing_recovery.dart';
import 'package:syncro_kiosk/src/kiosk/tablet.dart';

import 'support/fake_server.dart';

void main() {
  test('only a 401 KIOSK_NOT_PAIRED on a tablet route rejects the pairing', () {
    expect(
      isRejectedTabletSession(path: '/kiosk/api/heartbeat.php', statusCode: 401, hasTabletSession: true, code: 'KIOSK_NOT_PAIRED'),
      isTrue,
    );
    expect(
      isRejectedTabletSession(path: '/kiosk/api/pair.php', statusCode: 401, hasTabletSession: true, code: 'KIOSK_NOT_PAIRED'),
      isFalse,
    );
    expect(
      isRejectedTabletSession(path: '/kiosk/api/heartbeat.php', statusCode: 403, hasTabletSession: true, code: 'KIOSK_UNLICENSED'),
      isFalse,
    );
  });

  test('recovery drains first, then clears; a failed clear can be retried', () async {
    final order = <String>[];
    var failClear = true;
    final recovery = PairingRecovery(
      drain: () async => order.add('drain'),
      clearLocalPairing: () async {
        order.add('clear');
        if (failClear) throw StateError('busy');
      },
    );
    await expectLater(recovery.recover(), throwsA(isA<PairingRecoveryFailure>()));
    failClear = false;
    await recovery.recover();
    expect(order, ['drain', 'clear', 'drain', 'clear']);
  });

  test('recovery times out while work is still running', () async {
    final never = Completer<void>();
    final recovery = PairingRecovery(
      drain: () => never.future,
      clearLocalPairing: () async {},
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(recovery.recover(), throwsA(isA<PairingRecoveryFailure>()));
  });

  test('stored pairing round-trips and rejects incomplete data', () {
    final pairing = TabletPairing(
      accessToken: goodToken,
      tabletUuid: 'u',
      tablet: TabletInfo.fromJson(tabletJson),
    );
    final back = TabletPairing.fromStorageValue(pairing.toStorageValue());
    expect(back.accessToken, goodToken);
    expect(back.tablet.siteName, 'Head Office');
    expect(back.tablet.adminPinSet, isTrue);
    expect(
      () => TabletPairing.fromStorageValue('{"access_token":"","tablet_uuid":"u"}'),
      throwsFormatException,
    );
  });
}
