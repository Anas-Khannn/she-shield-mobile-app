import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException, SocketException;

import 'package:http/http.dart' as http;

import '../errors/app_exception.dart';
import 'api_config.dart';

/// HTTP response envelope returned by [ApiClient].
class ApiResponse {
  const ApiResponse({required this.statusCode, this.data});

  final int statusCode;
  final dynamic data;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Central HTTP layer for every request to the SheShield backend.
///
/// Widgets and controllers never talk to [http] directly — they go through
/// this class, which owns timeouts, JSON encoding/decoding, authorization
/// headers, status-code mapping, and (for idempotent requests) retries.
class ApiClient {
  ApiClient({
    ApiConfig? config,
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
    Future<bool> Function()? onRefreshToken,
    void Function()? onUnauthorized,
  })  : _config = config ?? ApiConfig.fromEnv(),
        _httpClient = httpClient ?? http.Client(),
        _tokenProvider = tokenProvider,
        _onRefreshToken = onRefreshToken,
        _onUnauthorized = onUnauthorized;

  final ApiConfig _config;
  final http.Client _httpClient;
  final Future<String?> Function()? _tokenProvider;

  /// Attempts to refresh the session. Returns true when a new access token
  /// was persisted. Must be safe to call concurrently — a single refresh is
  /// shared between all in-flight callers (no refresh storm).
  final Future<bool> Function()? _onRefreshToken;
  final void Function()? _onUnauthorized;

  Future<bool>? _refreshInFlight;

  ApiConfig get config => _config;

  Future<ApiResponse> get(
    String path, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool requiresAuth = false,
    bool retryOnNetworkError = true,
    int maxRetries = 2,
  }) {
    return _send(
      'GET',
      path,
      queryParameters: queryParameters,
      headers: headers,
      requiresAuth: requiresAuth,
      retryOnNetworkError: retryOnNetworkError,
      maxRetries: maxRetries,
    );
  }

  Future<ApiResponse> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool requiresAuth = false,
    int maxRetries = 1,
  }) {
    return _send(
      'POST',
      path,
      body: body,
      headers: headers,
      requiresAuth: requiresAuth,
      maxRetries: maxRetries,
    );
  }

  Future<ApiResponse> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool requiresAuth = false,
    int maxRetries = 1,
  }) {
    return _send(
      'PATCH',
      path,
      body: body,
      headers: headers,
      requiresAuth: requiresAuth,
      maxRetries: maxRetries,
    );
  }

  Future<ApiResponse> delete(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool requiresAuth = false,
    int maxRetries = 1,
  }) {
    return _send(
      'DELETE',
      path,
      body: body,
      headers: headers,
      requiresAuth: requiresAuth,
      maxRetries: maxRetries,
    );
  }

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool requiresAuth = false,
    bool retryOnNetworkError = false,
    int maxRetries = 1,
  }) async {
    final uri = Uri.parse('$_config.baseUrl$path')
        .replace(queryParameters: queryParameters);

    var attempt = 0;
    // A 401 may trigger a single session refresh followed by exactly one
    // retry. After that we accept the failure - no loop is possible.
    var tokenRefreshed = false;
    while (true) {
      attempt++;
      // A fresh request is needed for every attempt — http requests can only
      // be finalized once.
      final request = await _buildRequest(
        method,
        uri,
        body: body,
        headers: headers,
        requiresAuth: requiresAuth,
      );
      try {
        final response = await _httpClient.send(request).timeout(_config.timeout);
        final data = await _decode(response);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return ApiResponse(statusCode: response.statusCode, data: data);
        }
        if (requiresAuth && response.statusCode == 401 && !tokenRefreshed) {
          // The access token was rejected. Try ONE bounded refresh, then
          // retry this request a single time.
          tokenRefreshed = true;
          if (await _refreshSession()) {
            continue;
          }
        }
        if (requiresAuth && response.statusCode == 401) {
          // Refresh failed (or was already attempted) — the session is
          // really dead. Notify so the client can clear state and re-auth.
          _onUnauthorized?.call();
        }
        throw _exceptionFor(response.statusCode, data);
      } on ApiException {
        rethrow;
      } on TimeoutException {
        if (_shouldRetry(method, retryOnNetworkError, attempt, maxRetries)) {
          await _backoff(attempt);
          continue;
        }
        throw ApiTimeoutException(
          message: '$method $uri timed out after ${_config.timeout.inSeconds}s.',
        );
      } on SocketException catch (error) {
        if (_shouldRetry(method, retryOnNetworkError, attempt, maxRetries)) {
          await _backoff(attempt);
          continue;
        }
        throw NetworkException(message: '$method $uri failed: $error');
      } on IOException catch (error) {
        if (_shouldRetry(method, retryOnNetworkError, attempt, maxRetries)) {
          await _backoff(attempt);
          continue;
        }
        throw NetworkException(message: '$method $uri failed: $error');
      } on http.ClientException catch (error) {
        if (_shouldRetry(method, retryOnNetworkError, attempt, maxRetries)) {
          await _backoff(attempt);
          continue;
        }
        throw NetworkException(
          message: '$method $uri failed: ${error.message}',
          userMessage: 'No connection to the server. Please check your internet connection.',
        );
      } on FormatException catch (error) {
        throw InvalidDataException(
          message: 'Response body was not valid JSON: $error',
        );
      }
    }
  }

  Future<http.Request> _buildRequest(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool requiresAuth = false,
  }) async {
    final request = http.Request(method, uri);
    request.headers.addAll({'Accept': 'application/json', ...?headers});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (requiresAuth) {
      final token = await _tokenProvider?.call();
      if (token == null || token.isEmpty) {
        _onUnauthorized?.call();
        throw const AuthenticationException(
          message: 'No access token available.',
        );
      }
      request.headers['Authorization'] = 'Bearer $token';
    }
    return request;
  }

  Future<dynamic> _decode(http.StreamedResponse response) async {
    final text = await response.stream.bytesToString();
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  bool _shouldRetry(
    String method,
    bool retryOnNetworkError,
    int attempt,
    int maxRetries,
  ) {
    return method == 'GET' && retryOnNetworkError && attempt < maxRetries;
  }

  /// Refreshes the session once, sharing the in-flight operation between all
  /// callers so concurrent 401s never trigger a refresh storm.
  Future<bool> _refreshSession() async {
    final onRefreshToken = _onRefreshToken;
    if (onRefreshToken == null) return false;
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final future = _runRefresh(onRefreshToken);
    _refreshInFlight = future.whenComplete(() => _refreshInFlight = null);
    return future;
  }

  Future<bool> _runRefresh(Future<bool> Function() onRefreshToken) async {
    try {
      return await onRefreshToken();
    } catch (_) {
      // A refresh failure must degrade to the "session unusable" path, never
      // to an unhandled exception mid-request.
      return false;
    }
  }

  Future<void> _backoff(int attempt) {
    return Future<void>.delayed(Duration(milliseconds: 200 * attempt));
  }

  ApiException _exceptionFor(int statusCode, dynamic data) {
    final serverMessage = _serverMessage(data);

    switch (statusCode) {
      case 400:
        return ValidationException(
          statusCode: statusCode,
          message: serverMessage.isEmpty
              ? 'Bad request (400).'
              : 'Bad request: $serverMessage',
          userMessage: serverMessage.isEmpty
              ? 'The request was not accepted. Please check your details and try again.'
              : serverMessage,
        );
      case 401:
        // 401s on authenticated requests are handled higher up in _send
        // (bounded refresh + single retry). Anonymous 401s (bad login,
        // rejected refresh token) surface here without touching session state.
        return AuthenticationException(
          statusCode: statusCode,
          message: serverMessage.isEmpty
              ? 'Authentication failed (401).'
              : 'Authentication failed: $serverMessage',
          userMessage: serverMessage.isEmpty
              ? 'Your session has expired. Please sign in again.'
              : serverMessage,
        );
      case 403:
        return AuthorizationException(
          statusCode: statusCode,
          message: serverMessage.isEmpty
              ? 'Access denied (403).'
              : 'Access denied: $serverMessage',
          userMessage: serverMessage.isEmpty
              ? 'You do not have permission to do this.'
              : serverMessage,
        );
      case 404:
        return const NotFoundException(statusCode: 404);
      case 422:
        return ValidationException(
          statusCode: statusCode,
          message: serverMessage.isEmpty
              ? 'Unprocessable entity (422).'
              : 'Unprocessable entity: $serverMessage',
          userMessage: serverMessage.isEmpty
              ? 'The details you entered were not accepted. Please check them and try again.'
              : serverMessage,
        );
      case 429:
        return const RateLimitException(statusCode: 429);
      default:
        if (statusCode >= 500) {
          return ServerException(
            statusCode: statusCode,
            message: serverMessage.isEmpty
                ? 'Server error ($statusCode).'
                : 'Server error ($statusCode): $serverMessage',
          );
        }
        return ApiException(
          statusCode: statusCode,
          message: serverMessage.isEmpty
              ? 'Unexpected status ($statusCode).'
              : 'Unexpected status ($statusCode): $serverMessage',
        );
    }
  }

  String _serverMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return '';
  }
}