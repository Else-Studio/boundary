import 'package:boundary/model/error_models.dart';
import 'package:boundary/service/auth_service.dart';
import 'package:oauth2/oauth2.dart' as oauth2;

/// A factory for creating data model instances for testing purposes.
/// This is the single source of truth for test data, ensuring consistency
/// and making model changes easier to manage across the test suite.
class ModelFactory {
  /// Creates a standard, valid [User] instance with mock credentials.
  static User createUser({
    oauth2.Credentials? credentials,
  }) {
    return User(credentials ?? createCredentials());
  }

  /// Creates a standard, valid [oauth2.Credentials] object.
  static oauth2.Credentials createCredentials({
    String accessToken = 'mock-access-token',
    String? refreshToken = 'mock-refresh-token',
    DateTime? expiration,
  }) {
    return oauth2.Credentials(
      accessToken,
      refreshToken: refreshToken,
      // Expires in 1 hour by default
      expiration: expiration ?? DateTime.now().add(const Duration(hours: 1)),
    );
  }

  /// Creates an [HttpProblem] representing a 500 Internal Server Error.
  static HttpProblem createServerErrorProblem() {
    return const HttpProblem(
      title: 'Internal Server Error',
      status: 500,
      detail: 'An unexpected error occurred on the server.',
    );
  }

  /// Creates an [HttpProblem] representing a 404 Not Found error.
  static HttpProblem createNotFoundProblem() {
    return const HttpProblem(
      title: 'Not Found',
      status: 404,
      detail: 'The requested resource could not be found.',
    );
  }

  /// Creates a [Violation] instance for validation problems.
  static Violation createViolation({
    String field = 'username',
    String message = 'Username cannot be empty.',
  }) {
    return Violation(field: field, message: message);
  }

  /// Creates an [HttpValidationProblem] representing a 400 Bad Request
  /// due to validation errors.
  static HttpValidationProblem createValidationProblem({
    List<Violation>? violations,
    String detail = 'The input provided was invalid.',
  }) {
    return HttpValidationProblem(
      title: 'Validation Failed',
      status: 400,
      detail: detail,
      violations: violations ?? [createViolation()],
    );
  }
}
