/// Typed application errors.
///
/// Every failure surfaced by the app maps to one of these classes. Each error
/// carries a [message] intended for logs and a [userMessage] that is safe to
/// show directly to the user. Raw database/HTTP/socket exceptions are never
/// displayed in the UI.
sealed class AppException implements Exception {
  const AppException({required this.message, required this.userMessage});

  final String message;
  final String userMessage;

  @override
  String toString() => '$runtimeType: $message';
}

/// An error produced while the application is starting up.
class InitializationException extends AppException {
  const InitializationException({
    super.message = 'Application initialization failed.',
    super.userMessage = 'The app could not start. Please try again.',
  });
}

/// Missing, malformed, or insecure environment configuration.
class EnvironmentValidationException extends InitializationException {
  const EnvironmentValidationException({
    super.message = 'Invalid environment configuration.',
    super.userMessage = 'The app is not configured correctly. Please restart it.',
  });
}

/// Supabase could not be initialized after retries.
class SupabaseInitException extends InitializationException {
  const SupabaseInitException({
    super.message = 'Supabase initialization failed.',
    super.userMessage = 'We could not connect to the safety services. Please check your connection and try again.',
  });
}

/// The API base URL is insecure for the current environment (for example
/// plain HTTP configured for a production build).
class InsecureApiConfigException extends InitializationException {
  const InsecureApiConfigException({
    super.message = 'Insecure API configuration detected.',
    super.userMessage = 'The app configuration is insecure. Please contact support.',
  });
}

/// Base class for failures returned by or caused by the backend API.
class ApiException extends AppException {
  const ApiException({
    this.statusCode,
    super.message = 'The request failed.',
    super.userMessage = 'Something went wrong. Please try again.',
  });

  final int? statusCode;
}

/// The backend could not be reached at the network level.
class NetworkException extends ApiException {
  const NetworkException({
    super.statusCode,
    super.message = 'Could not reach the server.',
    super.userMessage = 'No connection to the server. Please check your internet connection.',
  });
}

/// The backend did not answer within the configured timeout window.
class ApiTimeoutException extends ApiException {
  const ApiTimeoutException({
    super.statusCode,
    super.message = 'The request timed out.',
    super.userMessage = 'The server is taking too long to respond. Please try again.',
  });
}

/// The request was not authenticated (HTTP 401).
class AuthenticationException extends ApiException {
  const AuthenticationException({
    super.statusCode,
    super.message = 'Authentication failed.',
    super.userMessage = 'Your session has expired. Please sign in again.',
  });
}

/// The authenticated user is not allowed to perform this action (HTTP 403).
class AuthorizationException extends ApiException {
  const AuthorizationException({
    super.statusCode,
    super.message = 'Access denied.',
    super.userMessage = 'You do not have permission to do this.',
  });
}

/// The requested resource does not exist (HTTP 404).
class NotFoundException extends ApiException {
  const NotFoundException({
    super.statusCode,
    super.message = 'The requested resource was not found.',
    super.userMessage = 'We could not find what you were looking for.',
  });
}

/// The request payload failed validation (HTTP 400 / 422).
class ValidationException extends ApiException {
  const ValidationException({
    super.statusCode,
    super.message = 'The request was invalid.',
    super.userMessage = 'The details you entered were not accepted. Please check them and try again.',
  });
}

/// Too many requests were sent (HTTP 429).
class RateLimitException extends ApiException {
  const RateLimitException({
    super.statusCode,
    super.message = 'Too many requests.',
    super.userMessage = 'You are sending too many requests. Please wait a moment and try again.',
  });
}

/// The backend reported a server-side failure (HTTP 500+).
class ServerException extends ApiException {
  const ServerException({
    super.statusCode,
    super.message = 'The server encountered an error.',
    super.userMessage = 'The server had a problem. Please try again in a moment.',
  });
}

/// The response body could not be understood.
class InvalidDataException extends ApiException {
  const InvalidDataException({
    super.statusCode,
    super.message = 'The server response was invalid.',
    super.userMessage = 'Unexpected server response. Please try again.',
  });
}