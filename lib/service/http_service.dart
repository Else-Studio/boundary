import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../utils.dart';
import 'auth_service.dart';

/// An exception representing a failed HTTP request.
/// It holds the raw [http.Response] to allow upstream services to inspect
/// the status code, body, and headers for detailed error handling.
class HttpException implements Exception {
  final http.Response response;

  /// Whether the call needed a token.
  final bool requireAuth;

  HttpException(this.response, {this.requireAuth = false});

  @override
  String toString() {
    return 'HttpException: Status Code: ${response.statusCode}, Uri: ${response.request?.url}';
  }
}

/// An exception representing a ClientException or other underlying exception by HTTP Client.
class ClientNetworkException implements Exception {
  final Exception e;

  ClientNetworkException(this.e);

  @override
  String toString() {
    return 'ClientNetworkException: $e';
  }
}

/// A low-level service for making HTTP requests.
///
/// This service is responsible for the transport layer of communication. It handles
/// attaching authentication tokens, setting default headers, and normalizing various
/// network-level errors (`TimeoutException`, `ClientException`) and unsuccessful
/// HTTP status codes into a predictable set of exceptions (`NetworkException`, `HttpException`)
/// for the `ApiClient` to consume. It also implements a retry mechanism for
/// transient errors like rate limiting (HTTP 429).
class HttpService {
  final AccessTokenProvider _tokens;
  final http.BaseClient _standardClient;

  final _logger = useLogger('Http');

  // --- Configuration Constants ---
  static const Duration _requestTimeout = Duration(seconds: 60);
  static const int _maxRetries = 3;
  static const Duration _baseRetryDelay = Duration(seconds: 2);

  HttpService(this._tokens, this._standardClient);

  Map<String, String> _mergeHeaders({
    Map<String, String>? customHeaders,
    Object? body,
  }) {
    return {
      if (body != null && customHeaders?['Content-Type'] == null)
        'Content-Type': 'application/json; charset=UTF-8',
      if (customHeaders?['Accept'] == null) 'Accept': 'application/json',
      ...?customHeaders,
    };
  }

  /// The 401 thrown when no token is available. Nothing is sent.
  HttpException _noTokenException(String method, Uri url) {
    final problemJson = jsonEncode({
      'type': 'about:blank',
      'title': 'Authentication Error',
      'status': 401,
      'detail': 'No access token.',
      'instance': null,
      'details': null,
    });
    return HttpException(
      http.Response(
        problemJson,
        401,
        headers: {'Content-Type': 'application/problem+json; charset=utf-8'},
        request: http.Request(method, url),
      ),
      requireAuth: true,
    );
  }

  /// Central private method to wrap all requests with unified error handling,
  /// timeout, and retry logic.
  ///
  /// With [requireAuth] the provider's token is sent as a bearer header. A 401
  /// goes to the provider and, when it gives a new token, is retried once. A
  /// call that cannot be sent twice ([resendable] false) skips both retries.
  Future<http.Response> _sendRequest(
    Future<http.Response> Function(
      http.BaseClient client,
      Map<String, String> authHeader,
    ) requestBuilder, {
    required String method,
    required Uri url,
    required bool requireAuth,
    bool resendable = true,
  }) async {
    String? token;
    if (requireAuth) {
      token = await _tokens.accessToken();
      if (token == null) {
        throw _noTokenException(method, url);
      }
    }
    var refreshed = false;
    var attempt = 0;
    while (attempt < _maxRetries) {
      try {
        final response = await requestBuilder(_standardClient, {
          if (token != null) 'Authorization': 'Bearer $token',
        }).timeout(_requestTimeout);

        _logResponse(response);
        _checkResponseStatus(response, requireAuth: requireAuth);
        return response; // Success, return the response immediately.
      } on TimeoutException catch (e, s) {
        _logger.error(
          'HttpService $method Error: Request timed out for $url',
          e,
          s,
        );
        // Do not retry on timeout, throw immediately.
        throw ClientNetworkException(e);
      } on http.ClientException catch (e, s) {
        _logger.error(
          'HttpService $method Error: Network/ClientException for $url',
          e,
          s,
        );
        // Do not retry on client exceptions, throw immediately.
        throw ClientNetworkException(e);
      } on HttpException catch (e) {
        if (requireAuth && e.response.statusCode == 401) {
          // Every 401 goes to the provider, the second one too, so a provider
          // that cannot refresh has signed out before the app sees the 401.
          final next = await _tokens.refreshAfterUnauthorized(token!);
          if (resendable && !refreshed && next != null) {
            token = next;
            refreshed = true;
            continue; // One retry; it does not count against the 429 retries.
          }
          rethrow;
        }
        // This is where the retry logic for specific status codes lives.
        if (resendable &&
            e.response.statusCode == 429 &&
            attempt < _maxRetries - 1) {
          final retryAfterHeader = e.response.headers['retry-after'];
          Duration delay;
          if (retryAfterHeader != null &&
              int.tryParse(retryAfterHeader) != null) {
            // Use the server-specified delay if available and valid.
            delay = Duration(seconds: int.parse(retryAfterHeader));
            _logger.warning(
              'Request to $url failed with 429. Server specified Retry-After: ${delay.inSeconds}s. Retrying... (Attempt ${attempt + 2})',
            );
          } else {
            // Fallback to exponential backoff.
            delay = _baseRetryDelay * pow(2, attempt);
            _logger.warning(
              'Request to $url failed with 429. Retrying in ${delay.inSeconds}s... (Attempt ${attempt + 2})',
            );
          }
          await Future.delayed(delay);
          attempt++;
          continue; // Continue to the next iteration of the loop.
        } else {
          // If it's not a 429 or it's the last attempt, rethrow the exception.
          rethrow;
        }
      } catch (e, s) {
        _logger.error(
          'HttpService $method Error: Unexpected error for $url',
          e,
          s,
        );
        // Do not retry on unexpected errors.
        throw HttpException(
          http.Response(
            'An unexpected error occurred: ${e.toString()}',
            500,
            request: http.Request(method, url),
          ),
          requireAuth: requireAuth,
        );
      }
    }
    // This part should be unreachable if _maxRetries > 0, but is a safeguard.
    throw ClientNetworkException(Exception('Exhausted all retry attempts.'));
  }

  /// Performs a GET request.
  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    _logger.verbose('HttpService GET: $url');
    final effectiveHeaders = _mergeHeaders(customHeaders: headers);
    return _sendRequest(
      (client, auth) =>
          client.get(url, headers: {...effectiveHeaders, ...auth}),
      method: 'GET',
      url: url,
      requireAuth: requireAuth,
    );
  }

  /// Performs a POST request.
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    bool requireAuth = true,
  }) async {
    _logger.verbose('HttpService POST: $url');
    final effectiveHeaders = _mergeHeaders(customHeaders: headers, body: body);
    return _sendRequest(
      (client, auth) =>
          client.post(url, headers: {...effectiveHeaders, ...auth}, body: body),
      method: 'POST',
      url: url,
      requireAuth: requireAuth,
    );
  }

  /// Performs a PUT request.
  Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    bool requireAuth = true,
  }) async {
    _logger.verbose('HttpService PUT: $url\nBody: $body');
    final effectiveHeaders = _mergeHeaders(customHeaders: headers, body: body);
    return _sendRequest(
      (client, auth) =>
          client.put(url, headers: {...effectiveHeaders, ...auth}, body: body),
      method: 'PUT',
      url: url,
      requireAuth: requireAuth,
    );
  }

  /// Performs a PATCH request.
  Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    bool requireAuth = true,
  }) async {
    _logger.verbose('HttpService PATCH: $url\nBody: $body');
    final effectiveHeaders = _mergeHeaders(customHeaders: headers, body: body);
    return _sendRequest(
      (client, auth) => client.patch(url,
          headers: {...effectiveHeaders, ...auth}, body: body),
      method: 'PATCH',
      url: url,
      requireAuth: requireAuth,
    );
  }

  /// Performs a DELETE request.
  Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    bool requireAuth = true,
  }) async {
    _logger.verbose('HttpService DELETE: $url');
    final effectiveHeaders = _mergeHeaders(customHeaders: headers, body: body);
    return _sendRequest(
      (client, auth) => client.delete(url,
          headers: {...effectiveHeaders, ...auth}, body: body),
      method: 'DELETE',
      url: url,
      requireAuth: requireAuth,
    );
  }

  /// Performs a multipart POST request with optional fields and files.
  Future<http.Response> postMultipart(
    Uri url, {
    Map<String, String>? headers,
    Map<String, String>? fields,
    required List<http.MultipartFile> files,
    bool requireAuth = true,
  }) async {
    _logger.verbose('HttpService POST (multipart): $url');
    final effectiveHeaders = _mergeHeaders(customHeaders: headers);

    return _sendRequest(
      (client, auth) async {
        final request = http.MultipartRequest('POST', url)
          ..headers.addAll({...effectiveHeaders, ...auth})
          ..fields.addAll(fields ?? {})
          ..files.addAll(files);

        final streamed = await client.send(request).timeout(_requestTimeout);
        return http.Response.fromStream(streamed);
      },
      method: 'POST',
      url: url,
      requireAuth: requireAuth,
      resendable: false,
    );
  }

  void _logResponse(http.Response response) {
    _logger.verbose(
      'Response: ${response.request?.method} ${response.request?.url} -> ${response.statusCode}',
    );
  }

  /// Throws [HttpException] for any non-2xx status code.
  void _checkResponseStatus(
    http.Response response, {
    required bool requireAuth,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(response, requireAuth: requireAuth);
    }
  }

  void dispose() {
    _standardClient.close();
  }
}
