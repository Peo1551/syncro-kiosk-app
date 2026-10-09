import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../config/app_config.dart';
import 'api_exception.dart';
import 'transport.dart';

export 'api_exception.dart';

class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.body,
    this.location,
    this.setCookies = const [],
    this.retryAfter,
  });

  final int statusCode;
  final String body;
  final String? location;
  final List<String> setCookies;
  final String? retryAfter;
}

/// A file sent with a multipart request (leave attachment).
class MultipartFile {
  const MultipartFile({
    required this.fieldName,
    required this.fileName,
    required this.contentType,
    required this.bytes,
  });

  final String fieldName;
  final String fileName;
  final String contentType;
  final List<int> bytes;
}

/// The employee app's ApiClient, rebuilt on an injectable transport. Same
/// method names, headers and error handling, plus the tablet's X-Kiosk-Token
/// on every request. A kiosk session that the server ends (401, auth_expired,
/// KIOSK_SESSION_ENDED, or a redirect to the login page) is reported once via
/// [onSessionEnded]; its cookie is then refused locally, like the employee
/// app's AuthRequestGuard.
class ApiClient {
  ApiClient({
    HttpTransport? transport,
    this.baseUrl = AppConfig.baseUrl,
    this.onSessionEnded,
  }) : transport = transport ?? const IoHttpTransport();

  final HttpTransport transport;
  final String baseUrl;
  void Function(String cookieHeader, ApiException error)? onSessionEnded;

  /// The tablet's access token, set once paired.
  String? kioskToken;

  final Set<String> _endedCookies = {};

  static const Duration _responseTimeout = Duration(seconds: 12);
  static const Duration _uploadTimeout = Duration(seconds: 20);

  Uri _uri(String path) {
    final trimmed = path.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Uri.parse(trimmed);
    }
    return Uri.parse(
      trimmed.startsWith('/') ? '$baseUrl$trimmed' : '$baseUrl/$trimmed',
    );
  }

  bool _isFirstParty(Uri uri) {
    final base = Uri.parse(baseUrl);
    return uri.scheme.toLowerCase() == base.scheme.toLowerCase() &&
        uri.host.toLowerCase() == base.host.toLowerCase();
  }

  /// Blocks a cookie locally, e.g. after sign-out.
  void endSession(String cookieHeader) {
    if (cookieHeader.isNotEmpty) _endedCookies.add(cookieHeader);
  }

  bool isEnded(String cookieHeader) => _endedCookies.contains(cookieHeader);

  Map<String, String> _headers(
    Uri uri, {
    required String accept,
    String? cookieHeader,
    String? csrfToken,
    String? contentType,
  }) {
    final headers = <String, String>{'accept': accept};
    if (contentType != null) headers['content-type'] = contentType;
    final token = (kioskToken ?? '').trim();
    if (token.isNotEmpty && _isFirstParty(uri)) {
      headers['x-kiosk-token'] = token;
    }
    final cookie = (cookieHeader ?? '').trim();
    if (cookie.isNotEmpty && _isFirstParty(uri)) {
      headers['cookie'] = cookie;
    }
    final csrf = (csrfToken ?? '').trim();
    if (csrf.isNotEmpty) headers['x-csrf-token'] = csrf;
    return headers;
  }

  void _check(String? cookieHeader) {
    final cookie = cookieHeader ?? '';
    if (cookie.isNotEmpty && _endedCookies.contains(cookie)) {
      throw const ApiException(
        'Your session has ended.',
        statusCode: 401,
        code: ApiException.sessionEndedCode,
      );
    }
  }

  Future<TransportResponse> _send(
    TransportRequest request, {
    String? cookieHeader,
  }) async {
    _check(cookieHeader);
    final TransportResponse response;
    try {
      response = await transport.send(request);
    } on TransportException catch (e) {
      throw ApiException(
        e.message,
        statusCode: e.timedOut ? 408 : null,
        isNetwork: true,
      );
    }
    _inspectSession(cookieHeader, response);
    return response;
  }

  /// Ends the employee session on the answers the server uses for it.
  void _inspectSession(String? cookieHeader, TransportResponse response) {
    final cookie = cookieHeader ?? '';
    if (cookie.isEmpty) return;
    final data = ApiException.decodeBody(response.body);
    final status = response.statusCode;
    final location = (response.header('location') ?? '').toLowerCase();
    final redirectedToLogin =
        const [301, 302, 303, 307, 308].contains(status) &&
        (location.contains('/login.php') || location.contains('/logout.php'));
    final ended =
        data['code'] == ApiException.sessionEndedCode ||
        (status == 401) ||
        (data['auth_expired'] == true && status >= 400) ||
        redirectedToLogin;
    if (!ended) return;
    final error = ApiException(
      (data['error'] ?? data['message'] ?? 'Your session has ended.')
          .toString(),
      statusCode: status == 403 ? 403 : 401,
      code: ApiException.sessionEndedCode,
    );
    final first = _endedCookies.add(cookie);
    if (first) onSessionEnded?.call(cookie, error);
    throw error;
  }

  Map<String, dynamic> _parseJsonResponse(TransportResponse response) {
    final failure = ApiException.fromResponse(
      response.statusCode,
      response.body,
      location: response.header('location'),
      retryAfterHeader: response.header('retry-after'),
    );
    if (failure != null) throw failure;
    final trimmed = response.body.trim();
    final json = ApiException.decodeBody(trimmed);
    if (json.isEmpty && trimmed.isNotEmpty) {
      final lower = trimmed.toLowerCase();
      if (lower.contains('<html') || lower.contains('<!doctype html')) {
        throw const ApiException(
          'Your session has ended.',
          statusCode: 401,
          code: ApiException.sessionEndedCode,
        );
      }
      throw const ApiException('Unexpected response from server.');
    }
    return json;
  }

  Future<Map<String, dynamic>> getJson({
    required String path,
    required String cookieHeader,
  }) async {
    final uri = _uri(path);
    final response = await _send(
      TransportRequest(
        method: 'GET',
        uri: uri,
        headers: _headers(
          uri,
          accept: 'application/json',
          cookieHeader: cookieHeader,
        ),
        timeout: _responseTimeout,
      ),
      cookieHeader: cookieHeader,
    );
    return _parseJsonResponse(response);
  }

  Future<ApiResponse> getRaw({
    required String path,
    String? cookieHeader,
  }) async {
    final uri = _uri(path);
    final response = await _send(
      TransportRequest(
        method: 'GET',
        uri: uri,
        headers: _headers(
          uri,
          accept: 'application/json,text/html',
          cookieHeader: cookieHeader,
        ),
        timeout: _responseTimeout,
      ),
      cookieHeader: cookieHeader,
    );
    return _toApiResponse(response);
  }

  Future<Map<String, dynamic>> postJsonBody({
    required String path,
    required String cookieHeader,
    required Map<String, dynamic> body,
    String? csrfToken,
  }) async {
    final uri = _uri(path);
    final response = await _send(
      TransportRequest(
        method: 'POST',
        uri: uri,
        headers: _headers(
          uri,
          accept: 'application/json',
          cookieHeader: cookieHeader,
          csrfToken: csrfToken,
          contentType: 'application/json; charset=utf-8',
        ),
        body: utf8.encode(jsonEncode(body)),
        timeout: _responseTimeout,
      ),
      cookieHeader: cookieHeader,
    );
    return _parseJsonResponse(response);
  }

  /// Raw JSON POST for the tablet endpoints: the caller reads the status,
  /// body and Set-Cookie itself.
  Future<ApiResponse> postJsonRaw({
    required String path,
    required Map<String, dynamic> body,
    String? cookieHeader,
    String? csrfToken,
    bool inspectSession = true,
  }) async {
    final uri = _uri(path);
    final request = TransportRequest(
      method: 'POST',
      uri: uri,
      headers: _headers(
        uri,
        accept: 'application/json',
        cookieHeader: cookieHeader,
        csrfToken: csrfToken,
        contentType: 'application/json; charset=utf-8',
      ),
      body: utf8.encode(jsonEncode(body)),
      timeout: _responseTimeout,
    );
    final response = inspectSession
        ? await _send(request, cookieHeader: cookieHeader)
        : await _sendWithoutSessionCheck(request);
    return _toApiResponse(response);
  }

  Future<TransportResponse> _sendWithoutSessionCheck(
    TransportRequest request,
  ) async {
    try {
      return await transport.send(request);
    } on TransportException catch (e) {
      throw ApiException(
        e.message,
        statusCode: e.timedOut ? 408 : null,
        isNetwork: true,
      );
    }
  }

  /// multipart/form-data POST, as the employee app's LeaveApi sends leave
  /// requests (with an optional attachment).
  Future<ApiResponse> postMultipart({
    required String path,
    required String cookieHeader,
    required Map<String, String> fields,
    MultipartFile? file,
    String? csrfToken,
  }) async {
    final uri = _uri(path);
    final boundary =
        '----syncrokiosk${DateTime.now().microsecondsSinceEpoch.toString()}';
    final body = BytesBuilder(copy: false);
    void write(String text) => body.add(utf8.encode(text));
    for (final entry in fields.entries) {
      write('--$boundary\r\n');
      write('Content-Disposition: form-data; name="${entry.key}"\r\n\r\n');
      write(entry.value);
      write('\r\n');
    }
    if (file != null) {
      write('--$boundary\r\n');
      write(
        'Content-Disposition: form-data; name="${file.fieldName}"; filename="${file.fileName}"\r\n',
      );
      write('Content-Type: ${file.contentType}\r\n\r\n');
      body.add(file.bytes);
      write('\r\n');
    }
    write('--$boundary--\r\n');
    final response = await _send(
      TransportRequest(
        method: 'POST',
        uri: uri,
        headers: _headers(
          uri,
          accept: 'application/json,text/html',
          cookieHeader: cookieHeader,
          csrfToken: csrfToken,
          contentType: 'multipart/form-data; boundary=$boundary',
        ),
        body: body.takeBytes(),
        timeout: _uploadTimeout,
      ),
      cookieHeader: cookieHeader,
    );
    return _toApiResponse(response);
  }

  ApiResponse _toApiResponse(TransportResponse response) {
    return ApiResponse(
      statusCode: response.statusCode,
      body: response.body,
      location: response.header('location'),
      setCookies: response.headerValues('set-cookie'),
      retryAfter: response.header('retry-after'),
    );
  }
}
