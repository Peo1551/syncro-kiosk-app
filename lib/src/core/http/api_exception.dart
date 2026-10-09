import 'dart:convert';

/// Error from a Syncro Connect request. Server failures carry `error` (human
/// text) and an optional `code`.
class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.retryAfterSeconds,
    this.isNetwork = false,
  });

  final String message;
  final int? statusCode;
  final String? code;

  /// Seconds to wait before trying again, from a 429 (Retry-After header or
  /// the body's retry_after).
  final int? retryAfterSeconds;

  /// No HTTP answer was received.
  final bool isNetwork;

  static const String sessionEndedCode = 'KIOSK_SESSION_ENDED';

  bool get isThrottled => statusCode == 429;
  bool get isSessionEnded => code == sessionEndedCode;
  bool get isNotPaired => code == 'KIOSK_NOT_PAIRED';
  bool get isUnlicensed => code == 'KIOSK_UNLICENSED';

  /// The phone app treats any 401 or a revoked session as an auth failure.
  bool get isAuthFailure => isSessionEnded || statusCode == 401;

  static Map<String, dynamic> decodeBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    try {
      final value = jsonDecode(trimmed);
      if (value is Map<String, dynamic>) return value;
    } catch (_) {}
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final value = jsonDecode(trimmed.substring(start, end + 1));
        if (value is Map<String, dynamic>) return value;
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  static int? parseRetryAfter(String? header, Map<String, dynamic> body) {
    final fromHeader = int.tryParse((header ?? '').trim());
    if (fromHeader != null && fromHeader > 0) return fromHeader;
    final raw = body['retry_after'];
    final fromBody = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    if (fromBody != null && fromBody > 0) return fromBody;
    return null;
  }

  /// Builds the failure for a response, or null when it is a success.
  static ApiException? fromResponse(
    int status,
    String body, {
    String? location,
    String? retryAfterHeader,
  }) {
    final data = decodeBody(body);
    final code = data['code']?.toString();
    final message = (data['error'] ?? data['message'] ?? '').toString().trim();
    if (status == 429) {
      return ApiException(
        message.isEmpty ? 'Too many attempts. Please wait.' : message,
        statusCode: 429,
        code: code,
        retryAfterSeconds: parseRetryAfter(retryAfterHeader, data),
      );
    }
    if (status >= 400) {
      return ApiException(
        message.isEmpty ? 'Request failed (HTTP $status).' : message,
        statusCode: status,
        code: code,
      );
    }
    if (const [301, 302, 303, 307, 308].contains(status)) {
      final target = (location ?? '').toLowerCase();
      if (target.contains('/login.php') || target.contains('/logout.php')) {
        return const ApiException(
          'Your session has ended.',
          statusCode: 401,
          code: sessionEndedCode,
        );
      }
      return ApiException('Unexpected redirect from server.', statusCode: status);
    }
    return null;
  }

  @override
  String toString() => message;
}
