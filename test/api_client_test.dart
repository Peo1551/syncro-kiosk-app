import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncro_kiosk/src/core/http/api_client.dart';
import 'package:syncro_kiosk/src/core/http/transport.dart';

import 'support/fake_server.dart';

class _OfflineTransport implements HttpTransport {
  @override
  Future<TransportResponse> send(TransportRequest request) async =>
      throw const TransportException('offline');
}

void main() {
  late FakeServer server;
  late ApiClient client;
  final ended = <String>[];

  setUp(() {
    server = FakeServer();
    ended.clear();
    client = ApiClient(transport: server)
      ..kioskToken = goodToken
      ..onSessionEnded = (cookie, _) => ended.add(cookie);
  });

  test('employee GET sends token, cookie and the employee app Accept', () async {
    server.json('/employee/status-json.php', {'ok': true});
    await client.getJson(
      path: '/employee/status-json.php',
      cookieHeader: 'PHPSESSID=a',
    );
    final req = server.requests.single;
    expect(req.uri.toString(), 'https://syncroconnect.com/employee/status-json.php');
    expect(req.headers['x-kiosk-token'], goodToken);
    expect(req.headers['cookie'], 'PHPSESSID=a');
    expect(req.headers['accept'], 'application/json');
  });

  test('JSON POST carries the CSRF header and body', () async {
    server.json('/employee/api/timesheet-approve.php', {'ok': true});
    await client.postJsonBody(
      path: '/employee/api/timesheet-approve.php',
      cookieHeader: 'PHPSESSID=a',
      csrfToken: 'tok',
      body: {'session_id': 9},
    );
    final req = server.requests.single;
    expect(req.headers['x-csrf-token'], 'tok');
    expect(jsonDecode(req.bodyText), {'session_id': 9});
  });

  test('server error text is surfaced', () async {
    server.json('/employee/api/timesheets.php', {
      'ok': false,
      'error': 'Timesheet viewing is not enabled for your mobile app group.',
    }, status: 403);
    expect(
      () => client.getJson(
        path: '/employee/api/timesheets.php',
        cookieHeader: 'PHPSESSID=a',
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', 403)
            .having((e) => e.isAuthFailure, 'auth', false)
            .having((e) => e.message, 'message', contains('not enabled')),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(ended, isEmpty);
  });

  test('KIOSK_SESSION_ENDED (any status) ends the session once and blocks the cookie', () async {
    server.json('/employee/api/leave-requests.php', {
      'ok': false,
      'auth_expired': true,
      'code': 'KIOSK_SESSION_ENDED',
      'error': 'You were signed out because the kiosk was left idle.',
    }, status: 403);
    await expectLater(
      client.getJson(
        path: '/employee/api/leave-requests.php',
        cookieHeader: 'PHPSESSID=a',
      ),
      throwsA(isA<ApiException>().having((e) => e.isSessionEnded, 'ended', true)),
    );
    expect(ended, ['PHPSESSID=a']);
    final before = server.requests.length;
    await expectLater(
      client.getJson(path: '/employee/status-json.php', cookieHeader: 'PHPSESSID=a'),
      throwsA(isA<ApiException>()),
    );
    expect(server.requests.length, before, reason: 'blocked locally');
    expect(ended.length, 1);
  });

  test('a plain 401 with auth_expired ends the session', () async {
    server.json('/employee/status-json.php', {
      'ok': false,
      'auth_expired': true,
      'message': 'Session expired. Please sign in again.',
    }, status: 401);
    await expectLater(
      client.getJson(path: '/employee/status-json.php', cookieHeader: 'c=1'),
      throwsA(isA<ApiException>().having((e) => e.isAuthFailure, 'auth', true)),
    );
    expect(ended, ['c=1']);
  });

  test('a redirect to the login page ends the session', () async {
    server.on(
      '/employee/api/holiday-summary.php',
      (_) => const TransportResponse(
        statusCode: 302,
        headers: {
          'location': ['/login.php'],
        },
      ),
    );
    await expectLater(
      client.getJson(path: '/employee/api/holiday-summary.php', cookieHeader: 'c=2'),
      throwsA(isA<ApiException>().having((e) => e.isSessionEnded, 'ended', true)),
    );
    expect(ended, ['c=2']);
  });

  test('a refused path (AUTH_ACCESS_DENIED) does not end the session', () async {
    server.json('/employee/history-json.php', {
      'ok': false,
      'code': 'AUTH_ACCESS_DENIED',
      'error': 'This is not available on Syncro Kiosk.',
    }, status: 403);
    await expectLater(
      client.getJson(path: '/employee/history-json.php', cookieHeader: 'c=3'),
      throwsA(isA<ApiException>()),
    );
    expect(ended, isEmpty);
  });

  test('429 reads Retry-After from header, then body', () async {
    server.json('/kiosk/api/sign-in.php', {
      'ok': false,
      'code': 'AUTH_THROTTLED',
      'error': 'Too many attempts.',
      'retry_after': 99,
    }, status: 429, headers: {'retry-after': ['120']});
    final res = await client.postJsonRaw(path: '/kiosk/api/sign-in.php', body: {});
    final e = ApiException.fromResponse(res.statusCode, res.body, retryAfterHeader: res.retryAfter)!;
    expect(e.isThrottled, isTrue);
    expect(e.retryAfterSeconds, 120);
    expect(ApiException.parseRetryAfter(null, {'retry_after': 30}), 30);
  });

  test('no answer is a network error', () async {
    final offline = ApiClient(transport: _OfflineTransport());
    await expectLater(
      offline.getJson(path: '/employee/status-json.php', cookieHeader: 'c'),
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', true)),
    );
  });

  test('multipart body holds the fields and the file', () async {
    server.json('/employee/api/leave-requests.php', {'ok': true});
    await client.postMultipart(
      path: '/employee/api/leave-requests.php',
      cookieHeader: 'c=4',
      csrfToken: 'x',
      fields: {'action': 'create', 'group_id': 'HOL'},
      file: const MultipartFile(
        fieldName: 'attachment',
        fileName: 'note.jpg',
        contentType: 'image/jpeg',
        bytes: [1, 2, 3],
      ),
    );
    final req = server.requests.single;
    expect(req.headers['content-type'], startsWith('multipart/form-data; boundary='));
    final text = latin1.decode(req.body!);
    expect(text, contains('name="action"\r\n\r\ncreate'));
    expect(text, contains('filename="note.jpg"'));
    expect(req.headers['x-kiosk-token'], goodToken);
  });

  test('the token is never sent to another host', () async {
    server.json('/x', {'ok': true});
    await client.getJson(path: 'https://example.com/x', cookieHeader: 'c=5');
    expect(server.requests.single.headers.containsKey('x-kiosk-token'), isFalse);
    expect(server.requests.single.headers.containsKey('cookie'), isFalse);
  });
}
