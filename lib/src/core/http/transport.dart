import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One HTTP request, kept free of dart:io so tests can answer it.
class TransportRequest {
  const TransportRequest({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
    this.timeout = const Duration(seconds: 12),
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int>? body;
  final Duration timeout;

  String get bodyText => body == null ? '' : utf8.decode(body!);
}

class TransportResponse {
  const TransportResponse({
    required this.statusCode,
    this.bodyBytes = const [],
    this.headers = const {},
  });

  factory TransportResponse.text(
    int statusCode,
    String body, {
    Map<String, List<String>> headers = const {},
  }) => TransportResponse(
    statusCode: statusCode,
    bodyBytes: utf8.encode(body),
    headers: headers,
  );

  final int statusCode;
  final List<int> bodyBytes;

  /// Header names are lower case. Set-Cookie keeps one entry per cookie.
  final Map<String, List<String>> headers;

  String get body => utf8.decode(bodyBytes, allowMalformed: true);

  String? header(String name) {
    final values = headers[name.toLowerCase()];
    return values == null || values.isEmpty ? null : values.first;
  }

  List<String> headerValues(String name) =>
      headers[name.toLowerCase()] ?? const [];
}

/// Thrown for a request that never got an HTTP answer (offline, DNS, TLS,
/// timeout). The request may or may not have reached the server.
class TransportException implements Exception {
  const TransportException(this.message, {this.timedOut = false});
  final String message;
  final bool timedOut;

  @override
  String toString() => message;
}

abstract class HttpTransport {
  Future<TransportResponse> send(TransportRequest request);
}

/// dart:io transport with the employee app's timeouts. Redirects are never
/// followed, so a redirect to the login page is seen as a lost session.
class IoHttpTransport implements HttpTransport {
  const IoHttpTransport();

  static const Duration _connectionTimeout = Duration(seconds: 6);

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    final client = HttpClient()..connectionTimeout = _connectionTimeout;
    try {
      final req = await client
          .openUrl(request.method, request.uri)
          .timeout(request.timeout);
      req.followRedirects = false;
      request.headers.forEach(req.headers.set);
      if (request.body != null) {
        req.add(request.body!);
      }
      final res = await req.close().timeout(request.timeout);
      final bytes = <int>[];
      await res.forEach(bytes.addAll).timeout(request.timeout);
      final headers = <String, List<String>>{};
      res.headers.forEach((name, values) {
        headers[name.toLowerCase()] = List<String>.of(values);
      });
      return TransportResponse(
        statusCode: res.statusCode,
        bodyBytes: bytes,
        headers: headers,
      );
    } on TimeoutException {
      throw const TransportException(
        'Request timed out. Please try again.',
        timedOut: true,
      );
    } on SocketException {
      throw const TransportException(
        'No connection to Syncro Connect. Check the tablet is online.',
      );
    } on HandshakeException {
      throw const TransportException('Secure connection failed.');
    } on HttpException {
      throw const TransportException('Connection to Syncro Connect failed.');
    } finally {
      client.close(force: true);
    }
  }
}
