import '../config/app_config.dart';
import '../core/http/api_client.dart';
import '../core/http/cookie_utils.dart';
import '../core/session.dart';
import 'pairing_flow.dart';
import 'tablet.dart';

/// Result of a successful pairing.
class PairResult {
  const PairResult({required this.accessToken, required this.tablet});
  final String accessToken;
  final TabletInfo tablet;
}

/// Calls the /kiosk/api/ tablet endpoints. Every call carries the tablet's
/// X-Kiosk-Token (set on the shared [ApiClient] once paired).
class KioskApi {
  KioskApi(this.client);

  final ApiClient client;

  Map<String, dynamic> _ok(ApiResponse response) {
    final failure = ApiException.fromResponse(
      response.statusCode,
      response.body,
      location: response.location,
      retryAfterHeader: response.retryAfter,
    );
    if (failure != null) throw failure;
    final json = ApiException.decodeBody(response.body);
    if (json['ok'] != true) {
      throw ApiException(
        (json['error'] ?? json['message'] ?? 'Unexpected response from server.')
            .toString(),
        statusCode: response.statusCode,
        code: json['code']?.toString(),
      );
    }
    return json;
  }

  /// A 5xx or a lost answer can follow a pairing the server committed, so it
  /// is reported as uncertain (as the visitor tablet does).
  Future<PairResult> pair({
    required String pairingCode,
    required String tabletUuid,
    required String appVersion,
  }) async {
    Map<String, dynamic> json;
    try {
      json = _ok(
        await client.postJsonRaw(
          path: AppConfig.pairPath,
          body: {
            'pairing_code': pairingCode,
            'tablet_uuid': tabletUuid,
            'app_version': appVersion,
          },
        ),
      );
    } on ApiException catch (e) {
      if (e.isNetwork || e.statusCode == null || e.statusCode! >= 500) {
        throw const PairingUncertain();
      }
      throw PairingFailure(_pairMessage(e));
    } catch (_) {
      throw const PairingUncertain();
    }
    final token = (json['access_token'] ?? '').toString().trim();
    if (token.isEmpty) throw const PairingUncertain();
    return PairResult(
      accessToken: token,
      tablet: TabletInfo.fromJson(json['tablet']),
    );
  }

  String _pairMessage(ApiException e) {
    if (e.isThrottled) {
      return throttleMessage(e.retryAfterSeconds);
    }
    return e.message;
  }

  Future<TabletInfo> heartbeat({required String appVersion}) async {
    final json = _ok(
      await client.postJsonRaw(
        path: AppConfig.heartbeatPath,
        body: {'app_version': appVersion},
      ),
    );
    return TabletInfo.fromJson(json['tablet']);
  }

  Future<void> checkAdminPin(String pin) async {
    _ok(
      await client.postJsonRaw(
        path: AppConfig.adminPinPath,
        body: {'pin': pin.trim()},
      ),
    );
  }

  Future<void> unpair(String pin) async {
    _ok(
      await client.postJsonRaw(
        path: AppConfig.unpairPath,
        body: {'pin': pin.trim()},
      ),
    );
  }

  Future<AppSession> signInWithCard(String card) =>
      _signIn({'card': card.trim()});

  Future<AppSession> signInWithPin({
    required String clockNumber,
    required String pin,
  }) => _signIn({'clock_number': clockNumber.trim(), 'pin': pin.trim()});

  Future<AppSession> _signIn(Map<String, dynamic> body) async {
    final response = await client.postJsonRaw(
      path: AppConfig.signInPath,
      body: body,
      inspectSession: false,
    );
    final json = _ok(response);
    final cookie = buildCookieHeader(response.setCookies);
    if (cookie.isEmpty) {
      throw const ApiException(
        'Sign-in did not start a session. Please try again.',
      );
    }
    final session = json['session'] is Map
        ? (json['session'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    int? toInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    final idle = toInt(json['idle_seconds']) ?? 0;
    return AppSession(
      cookieHeader: cookie,
      csrf: (json['csrf'] ?? '').toString(),
      companyId: toInt(session['company_id']),
      employeeId: toInt(session['employee_id']),
      employeeFirstName: (session['first_name'] ?? '').toString(),
      employeeLastName: (session['last_name'] ?? '').toString(),
      idleSeconds: idle > 0 ? idle : AppConfig.defaultIdleSeconds,
    );
  }

  /// Fire and forget: the tablet moves on whatever the answer.
  Future<void> signOut(String cookieHeader) async {
    try {
      await client.postJsonRaw(
        path: AppConfig.signOutPath,
        body: const {},
        cookieHeader: cookieHeader,
        inspectSession: false,
      );
    } catch (_) {}
  }
}

String throttleMessage(int? retryAfterSeconds) {
  final wait = retryAfterSeconds;
  if (wait == null || wait <= 0) return 'Too many attempts, please wait.';
  if (wait < 90) {
    return 'Too many attempts, please wait $wait ${wait == 1 ? 'second' : 'seconds'}.';
  }
  final minutes = (wait / 60).ceil();
  return 'Too many attempts, please wait $minutes minutes.';
}
