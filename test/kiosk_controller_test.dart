import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro_kiosk/src/app/kiosk_controller.dart';
import 'package:syncro_kiosk/src/core/http/api_client.dart';
import 'package:syncro_kiosk/src/kiosk/pairing_flow.dart';
import 'package:syncro_kiosk/src/kiosk/tablet.dart';
import 'package:syncro_kiosk/src/kiosk/tablet_store.dart';

import 'support/fake_server.dart';

TabletPairing savedPairing() => TabletPairing(
  accessToken: goodToken,
  tabletUuid: 'uuid-1',
  tablet: TabletInfo.fromJson(tabletJson),
);

KioskController makeController(FakeServer server, MemoryTabletStore store) {
  return KioskController(
    client: ApiClient(transport: server),
    store: store,
    appVersion: '1.0.0+1',
  );
}

void main() {
  group('pairing', () {
    test('an unpaired tablet starts on Pair; pairing saves and goes to wake', () async {
      final server = workingServer();
      final store = MemoryTabletStore();
      final c = makeController(server, store);
      await c.start();
      expect(c.mode, KioskMode.pair);
      await c.pair('123456');
      expect(c.mode, KioskMode.wake);
      expect(store.pairing!.accessToken, goodToken);
      expect(store.pairing!.tabletUuid, 'test-tablet-uuid');
      expect(c.tablet.companyName, 'Computime');
      expect(c.client.kioskToken, goodToken);
      await Future<void>.delayed(Duration.zero);
      expect(server.to('/kiosk/api/heartbeat.php').single.headers['x-kiosk-token'], goodToken);
      c.dispose();
    });

    test('an uncertain pairing blocks the same code but keeps a received token for saving', () async {
      final server = workingServer();
      server.json('/kiosk/api/pair.php', {'ok': false}, status: 502);
      final store = MemoryTabletStore();
      final c = makeController(server, store);
      await c.start();
      await expectLater(c.pair('111111'), throwsA(isA<PairingUncertain>()));
      final calls = server.to('/kiosk/api/pair.php').length;
      await expectLater(c.pair('111111'), throwsA(isA<PairingUncertain>()));
      expect(server.to('/kiosk/api/pair.php').length, calls, reason: 'not re-sent');
      expect(store.pairing, isNull);
      c.dispose();
    });

    test('a failed save is retried without pairing again', () async {
      final server = workingServer();
      final store = _FlakyStore();
      final c = makeController(server, store);
      await c.start();
      await expectLater(c.pair('123456'), throwsA(isA<PairingFailure>()));
      expect(server.to('/kiosk/api/pair.php').length, 1);
      store.fail = false;
      await c.pair('999999');
      expect(server.to('/kiosk/api/pair.php').length, 1);
      expect(store.pairing, isNotNull);
      expect(c.mode, KioskMode.wake);
      c.dispose();
    });

    test('heartbeat 401 KIOSK_NOT_PAIRED wipes the pairing and goes to Pair', () async {
      final server = workingServer();
      server.json('/kiosk/api/heartbeat.php', {
        'ok': false,
        'code': 'KIOSK_NOT_PAIRED',
        'error': 'This tablet is not paired or has been removed.',
      }, status: 401);
      final store = MemoryTabletStore(pairing: savedPairing());
      final c = makeController(server, store);
      await c.start();
      await c.heartbeat();
      expect(c.mode, KioskMode.pair);
      expect(store.pairing, isNull);
      expect(c.client.kioskToken, isNull);
      c.dispose();
    });

    test('heartbeat 403 KIOSK_UNLICENSED blocks, keeps the pairing, and recovers', () async {
      final server = workingServer();
      server.json('/kiosk/api/heartbeat.php', {
        'ok': false,
        'code': 'KIOSK_UNLICENSED',
        'error': 'Syncro Kiosk is not active for this company.',
      }, status: 403);
      final store = MemoryTabletStore(pairing: savedPairing());
      final c = makeController(server, store);
      await c.start();
      await c.heartbeat();
      expect(c.mode, KioskMode.unlicensed);
      expect(store.pairing, isNotNull);
      server.json('/kiosk/api/heartbeat.php', {'ok': true, 'tablet': tabletJson});
      await c.heartbeat();
      expect(c.mode, KioskMode.wake);
      c.dispose();
    });

    test('heartbeat refreshes tablet details; offline is ignored', () async {
      final server = workingServer();
      server.json('/kiosk/api/heartbeat.php', {
        'ok': true,
        'tablet': {...tabletJson, 'site_name': 'Depot', 'idle_seconds': 120},
      });
      final store = MemoryTabletStore(pairing: savedPairing());
      final c = makeController(server, store);
      await c.start();
      await c.heartbeat();
      expect(c.tablet.siteName, 'Depot');
      expect(c.tabletIdleSeconds, 120);
      server.routes.remove('/kiosk/api/heartbeat.php');
      server.on('/kiosk/api/heartbeat.php', (_) => throw Exception('offline'));
      await c.heartbeat();
      expect(c.mode, KioskMode.wake);
      c.dispose();
    });
  });

  group('sign-in flow', () {
    test('card sign-in opens a session with the server idle time', () {
      fakeAsync((async) {
        final server = workingServer();
        final c = makeController(server, MemoryTabletStore(pairing: savedPairing()));
        c.start();
        async.flushMicrotasks();
        c.openSignIn();
        expect(c.idle.limit, 45, reason: 'tablet idle on the sign-in screen');
        c.signInWithCard('A1B2C3');
        async.flushMicrotasks();
        expect(c.mode, KioskMode.signedIn);
        expect(c.session!.employeeId, 42);
        expect(c.idle.remaining.value, 120);
        async.elapse(const Duration(seconds: 10));
        expect(c.idle.remaining.value, 110);
        c.touch();
        expect(c.idle.remaining.value, 120);
        c.dispose();
      });
    });

    test('errors show inline with the server text', () async {
      final server = workingServer();
      server.json('/kiosk/api/sign-in.php', {
        'ok': false,
        'code': 'KIOSK_CARD_UNKNOWN',
        'error': 'That card is not recognised.',
      }, status: 401);
      final c = makeController(server, MemoryTabletStore(pairing: savedPairing()));
      await c.start();
      c.openSignIn();
      await c.signInWithCard('ZZZZ');
      expect(c.mode, KioskMode.signIn);
      expect(c.signInError, 'That card is not recognised.');
      expect(c.session, isNull);
      c.dispose();
    });

    test('429 shows the wait and blocks retries until it passes', () async {
      final server = workingServer();
      server.json('/kiosk/api/sign-in.php', {'ok': false, 'error': 'Too many.'},
          status: 429, headers: {'retry-after': ['600']});
      final c = makeController(server, MemoryTabletStore(pairing: savedPairing()));
      await c.start();
      c.openSignIn();
      await c.signInWithPin(clockNumber: '12', pin: '1234');
      expect(c.signInError, 'Too many attempts, please wait 10 minutes.');
      expect(c.signInBlocked, isTrue);
      c.dispose();
    });

    test('sign-in KIOSK_ACCESS_DENIED stays on sign-in', () async {
      final server = workingServer();
      server.json('/kiosk/api/sign-in.php', {
        'ok': false,
        'code': 'KIOSK_ACCESS_DENIED',
        'error': 'This account cannot use Syncro Kiosk.',
      }, status: 403);
      final c = makeController(server, MemoryTabletStore(pairing: savedPairing()));
      await c.start();
      c.openSignIn();
      await c.signInWithCard('1234');
      expect(c.mode, KioskMode.signIn);
      expect(c.signInError, contains('cannot use'));
      c.dispose();
    });

    test('sign-in unlicensed shows the blocking screen', () async {
      final server = workingServer();
      server.json('/kiosk/api/sign-in.php', {
        'ok': false,
        'code': 'KIOSK_UNLICENSED',
        'error': 'Not active.',
      }, status: 403);
      final c = makeController(server, MemoryTabletStore(pairing: savedPairing()));
      await c.start();
      c.openSignIn();
      await c.signInWithCard('1234');
      expect(c.mode, KioskMode.unlicensed);
      c.dispose();
    });

    test('sign-out clears the session, calls the server, then wakes after 3s', () {
      fakeAsync((async) {
        final server = workingServer();
        final store = MemoryTabletStore(pairing: savedPairing());
        final c = makeController(server, store);
        c.start();
        async.flushMicrotasks();
        c.openSignIn();
        c.signInWithCard('A1B2');
        async.flushMicrotasks();
        final cookie = c.session!.cookieHeader;
        c.signOut();
        async.flushMicrotasks();
        expect(c.session, isNull);
        expect(c.mode, KioskMode.signedOut);
        expect(server.to('/kiosk/api/sign-out.php').single.headers['cookie'], cookie);
        expect(c.client.isEnded(cookie), isTrue);
        async.elapse(const Duration(seconds: 3));
        expect(c.mode, KioskMode.wake);
        // Only the pairing is stored.
        expect(store.pairing!.toStorageValue(), isNot(contains('Sam')));
        c.dispose();
      });
    });

    test('idle on a signed-in screen signs out', () {
      fakeAsync((async) {
        final server = workingServer();
        final c = makeController(server, MemoryTabletStore(pairing: savedPairing()));
        c.start();
        async.flushMicrotasks();
        c.openSignIn();
        c.signInWithCard('A1B2');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 119));
        expect(c.mode, KioskMode.signedIn);
        async.elapse(const Duration(seconds: 1));
        expect(c.mode, KioskMode.signedOut);
        expect(c.signedOutMessage, contains('idle'));
        expect(server.to('/kiosk/api/sign-out.php'), hasLength(1));
        c.dispose();
      });
    });

    test('idle on the sign-in and admin screens returns to wake', () {
      fakeAsync((async) {
        final c = makeController(workingServer(), MemoryTabletStore(pairing: savedPairing()));
        c.start();
        async.flushMicrotasks();
        c.openSignIn();
        async.elapse(const Duration(seconds: 45));
        expect(c.mode, KioskMode.wake);
        c.openAdminPin();
        async.elapse(const Duration(seconds: 44));
        expect(c.mode, KioskMode.adminPin);
        async.elapse(const Duration(seconds: 1));
        expect(c.mode, KioskMode.wake);
        c.dispose();
      });
    });

    test('a session the server ends goes to the signed-out screen', () {
      fakeAsync((async) {
        final server = workingServer();
        server.json('/employee/status-json.php', {
          'ok': false,
          'auth_expired': true,
          'code': 'KIOSK_SESSION_ENDED',
          'error': 'You were signed out because the kiosk was left idle.',
        }, status: 401);
        final c = makeController(server, MemoryTabletStore(pairing: savedPairing()));
        c.start();
        async.flushMicrotasks();
        c.openSignIn();
        c.signInWithCard('A1B2');
        async.flushMicrotasks();
        c.client
            .getJson(path: '/employee/status-json.php', cookieHeader: c.session!.cookieHeader)
            .catchError((Object _) => <String, dynamic>{});
        async.flushMicrotasks();
        expect(c.mode, KioskMode.signedOut);
        expect(c.session, isNull);
        expect(server.to('/kiosk/api/sign-out.php'), hasLength(1));
        c.dispose();
      });
    });

    test('sending the app to the background signs the employee out', () async {
      final c = makeController(workingServer(), MemoryTabletStore(pairing: savedPairing()));
      await c.start();
      c.openSignIn();
      await c.signInWithCard('A1B2');
      c.onAppPaused();
      await Future<void>.delayed(Duration.zero);
      expect(c.session, isNull);
      c.dispose();
    });

    test('a card tap on the wake screen signs in', () {
      fakeAsync((async) {
        final server = workingServer();
        final c = makeController(server, MemoryTabletStore(pairing: savedPairing()));
        c.start();
        async.flushMicrotasks();
        expect(c.mode, KioskMode.wake);
        c.cardReader.onCard('0012345678');
        async.flushMicrotasks();
        expect(c.mode, KioskMode.signedIn);
        expect(server.to('/kiosk/api/sign-in.php'), hasLength(1));
        c.dispose();
      });
    });
  });

  group('admin', () {
    test('the PIN is checked by the server', () async {
      final server = workingServer();
      server.json('/kiosk/api/admin-pin.php', {
        'ok': false,
        'code': 'KIOSK_PIN_WRONG',
        'error': 'That PIN is not right.',
      }, status: 401);
      final c = makeController(server, MemoryTabletStore(pairing: savedPairing()));
      await c.start();
      c.openAdminPin();
      expect(await c.checkAdminPin('0000'), 'That PIN is not right.');
      expect(c.mode, KioskMode.adminPin);
      server.json('/kiosk/api/admin-pin.php', {'ok': true});
      expect(await c.checkAdminPin('1234'), isNull);
      expect(c.mode, KioskMode.admin);
      c.dispose();
    });

    test('no admin PIN set: the server text is shown', () async {
      final server = workingServer();
      server.json('/kiosk/api/admin-pin.php', {
        'ok': false,
        'code': 'KIOSK_ADMIN_PIN_NOT_SET',
        'error': 'No kiosk admin PIN has been set.',
      }, status: 409);
      final c = makeController(server, MemoryTabletStore(pairing: savedPairing()));
      await c.start();
      expect(await c.checkAdminPin('1234'), 'No kiosk admin PIN has been set.');
      c.dispose();
    });

    test('unpair wipes the pairing; 409 leaves it and shows why', () async {
      final server = workingServer();
      final store = MemoryTabletStore(pairing: savedPairing());
      final c = makeController(server, store);
      await c.start();
      server.json('/kiosk/api/unpair.php', {
        'ok': false,
        'code': 'KIOSK_ADMIN_PIN_NOT_SET',
        'error': 'Remove this tablet in Syncro Connect (Settings, Syncro Kiosk).',
      }, status: 409);
      expect(await c.unpair('1234'), contains('Remove this tablet'));
      expect(store.pairing, isNotNull);
      server.json('/kiosk/api/unpair.php', {'ok': true});
      expect(await c.unpair('1234'), isNull);
      expect(store.pairing, isNull);
      expect(c.mode, KioskMode.pair);
      c.dispose();
    });
  });
}

class _FlakyStore extends MemoryTabletStore {
  bool fail = true;

  @override
  Future<void> savePairing(TabletPairing next) async {
    if (fail) throw StateError('keystore busy');
    await super.savePairing(next);
  }
}
