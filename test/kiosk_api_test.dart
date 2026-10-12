import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncro_kiosk/src/core/http/api_client.dart';
import 'package:syncro_kiosk/src/core/http/transport.dart';
import 'package:syncro_kiosk/src/kiosk/kiosk_api.dart';
import 'package:syncro_kiosk/src/kiosk/pairing_flow.dart';

import 'support/fake_server.dart';

void main() {
  late FakeServer server;
  late KioskApi api;

  setUp(() {
    server = workingServer();
    api = KioskApi(ApiClient(transport: server));
  });

  group('pair', () {
    test('returns the token and tablet details', () async {
      final result = await api.pair(
        pairingCode: '123456',
        tabletUuid: 'uuid-1',
        appVersion: '1.0.0+1',
      );
      expect(result.accessToken, goodToken);
      expect(result.tablet.companyName, 'Computime');
      expect(result.tablet.placeLabel, 'Computime · Head Office');
      expect(result.tablet.idleSeconds, 45);
      final body = jsonDecode(server.requests.single.bodyText);
      expect(body, {
        'pairing_code': '123456',
        'tablet_uuid': 'uuid-1',
        'app_version': '1.0.0+1',
      });
    });

    test('a wrong code is a plain failure with the server text', () async {
      server.json('/kiosk/api/pair.php', {
        'ok': false,
        'code': 'KIOSK_CODE_INVALID',
        'error': 'That pairing code is wrong or has expired.',
      }, status: 401);
      expect(
        () => api.pair(pairingCode: '1', tabletUuid: 'u', appVersion: ''),
        throwsA(
          isA<PairingFailure>()
              .having((e) => e is PairingUncertain, 'uncertain', false)
              .having((e) => e.message, 'message', contains('wrong')),
        ),
      );
    });

    test('unlicensed is a plain failure', () async {
      server.json('/kiosk/api/pair.php', {
        'ok': false,
        'code': 'KIOSK_UNLICENSED',
        'error': 'Syncro Kiosk is not active for this company.',
      }, status: 403);
      expect(
        () => api.pair(pairingCode: '1', tabletUuid: 'u', appVersion: ''),
        throwsA(isA<PairingFailure>().having((e) => e.message, 'm', contains('not active'))),
      );
    });

    test('throttled shows the wait', () async {
      server.json('/kiosk/api/pair.php', {'ok': false, 'error': 'x'},
          status: 429, headers: {'retry-after': ['40']});
      expect(
        () => api.pair(pairingCode: '1', tabletUuid: 'u', appVersion: ''),
        throwsA(isA<PairingFailure>().having((e) => e.message, 'm', contains('40 seconds'))),
      );
    });

    test('5xx and lost answers are uncertain', () async {
      server.json('/kiosk/api/pair.php', {'ok': false}, status: 500);
      await expectLater(
        api.pair(pairingCode: '1', tabletUuid: 'u', appVersion: ''),
        throwsA(isA<PairingUncertain>()),
      );
      server.on('/kiosk/api/pair.php', (_) => throw const TransportException('x'));
      await expectLater(
        api.pair(pairingCode: '1', tabletUuid: 'u', appVersion: ''),
        throwsA(isA<PairingUncertain>()),
      );
      server.json('/kiosk/api/pair.php', {'ok': true});
      await expectLater(
        api.pair(pairingCode: '1', tabletUuid: 'u', appVersion: ''),
        throwsA(isA<PairingUncertain>()),
      );
    });
  });

  group('sign-in', () {
    test('card sign-in captures cookie, CSRF, names and idle time', () async {
      final session = await api.signInWithCard(' 00A1B2 ');
      expect(session.cookieHeader, 'PHPSESSID=sess-1');
      expect(session.csrf, 'csrf-1');
      expect(session.employeeId, 42);
      expect(session.fullName, 'Sam Taylor');
      expect(session.initials, 'ST');
      expect(session.idleSeconds, 120);
      final req = server.requests.single;
      expect(jsonDecode(req.bodyText), {'card': '00A1B2'});
      expect(req.headers.containsKey('cookie'), isFalse);
    });

    test('clock number and PIN are sent together', () async {
      await api.signInWithPin(clockNumber: '1234', pin: '9876');
      expect(jsonDecode(server.requests.single.bodyText), {
        'clock_number': '1234',
        'pin': '9876',
      });
    });

    test('server errors keep their text and code', () async {
      server.json('/kiosk/api/sign-in.php', {
        'ok': false,
        'code': 'KIOSK_PIN_WRONG',
        'error': 'Clock number or PIN is not right.',
      }, status: 401);
      expect(
        () => api.signInWithPin(clockNumber: '1', pin: '0000'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'KIOSK_PIN_WRONG')
              .having((e) => e.message, 'message', 'Clock number or PIN is not right.'),
        ),
      );
    });

    test('a success with no cookie is refused', () async {
      server.json('/kiosk/api/sign-in.php', {'ok': true, 'session': {}});
      expect(() => api.signInWithCard('1234'), throwsA(isA<ApiException>()));
    });
  });

  test('sign-out sends the cookie and never throws', () async {
    await api.signOut('PHPSESSID=x');
    expect(server.requests.single.headers['cookie'], 'PHPSESSID=x');
    server.on('/kiosk/api/sign-out.php', (_) => throw const TransportException('x'));
    await api.signOut('PHPSESSID=x');
  });

  test('unpair without an admin PIN set shows the server text', () async {
    server.json('/kiosk/api/unpair.php', {
      'ok': false,
      'code': 'KIOSK_ADMIN_PIN_NOT_SET',
      'error': 'Remove this tablet in Syncro Connect under Settings, Syncro Kiosk.',
    }, status: 409);
    expect(
      () => api.unpair('1234'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'KIOSK_ADMIN_PIN_NOT_SET')),
    );
  });

  test('throttle message wording', () {
    expect(throttleMessage(null), 'Too many attempts, please wait.');
    expect(throttleMessage(1), 'Too many attempts, please wait 1 second.');
    expect(throttleMessage(45), 'Too many attempts, please wait 45 seconds.');
    expect(throttleMessage(900), 'Too many attempts, please wait 15 minutes.');
  });
}
