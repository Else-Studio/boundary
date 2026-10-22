import 'dart:async';
import 'dart:convert';

import 'package:boundary/utils.dart';
import 'package:flutter/foundation.dart' show protected;
import 'package:http/http.dart' as http;

import '../model/app_config.dart';
import '../model/error_models.dart';
import 'http_service.dart';

// ===================================================================
// 1. Generic Business-Level Exception Classes
//    These are part of the core framework because they represent common
//    API states, not application-specific business logic.
// ===================================================================

/// **Base class** for all API-related exceptions.
class ApiException implements Exception {
  final String? message;
  final HttpProblem? problem;

  ApiException(this.message, {this.problem});

  @override
  String toString() => message ?? problem?.title ?? runtimeType.toString();
}

/// Thrown for client-side network errors (e.g., no internet, DNS failure, timeout).
class NetworkException extends ApiException {
  NetworkException({String? details})
      : super(
          "Could not connect. Please check your network connection.${details != null ? " Details: $details" : ""}",
        );
}

/// Thrown when the user's session is no longer valid.
class SessionTerminatedException extends ApiException {
  SessionTerminatedException({super.problem})
      : super(
          problem?.detail ?? "Your session has expired. Please log in again.",
        );
}

/// A 401 on a call that needed no token, e.g. a refused login.
class CredentialsRejectedException extends ApiException {
  CredentialsRejectedException({super.problem})
      : super(problem?.detail ?? 'The sign-in details were not accepted.');
}

/// Thrown when the user does not have permission to access a resource (HTTP 403).
class ForbiddenException extends ApiException {
  ForbiddenException({super.problem})
      : super(
          problem?.detail ?? "You do not have permission to access this resource.",
        );
}

/// Thrown when a specific resource is not found (HTTP 404).
class ResourceNotFoundException extends ApiException {
  ResourceNotFoundException(String resource, {super.problem})
      : super("$resource not found.");
}

/// Thrown when the server reports a validation error.
class InvalidInputException extends ApiException {
  final HttpValidationProblem? validationProblem;

  InvalidInputException(String super.message, {this.validationProblem})
      : super(problem: validationProblem);
}

/// Thrown for a generic 5xx server error.
class ServerUnavailableException extends ApiException {
  ServerUnavailableException({super.problem})
      : super(
          "The server is currently unavailable. Please try again later.",
        );
}

/// Thrown when an HTTP 429 is received after all retries.
class RateLimitExceededException extends ApiException {
  RateLimitExceededException({super.problem})
      : super(
          "You are making too many requests. Please wait a moment and try again.",
        );
}

/// Thrown when the API response cannot be parsed, indicating a client-server contract violation.
class DataParsingException extends ApiException {
  DataParsingException(String details)
      : super("Failed to parse API response: $details");
}

// ===================================================================
// 2. The Base API Client (The Generic Engine)
//    - This abstract class provides the shared implementation for any API
//      client that communicates over HTTP.
//    - The application-specific client (e.g., `LiveApiClient`) will EXTEND this class.
//    - The application will also define its own separate contract, e.g.,
//      `abstract class ApiClient { ... }`, which both `LiveApiClient` and
//      `SimulatedApiClient` will IMPLEMENT.
// ===================================================================
abstract class BaseApiClient with ApiUriBuilder {
  final HttpService httpService;
  final String baseUrl;

  @override
  String get apiBaseUrl => baseUrl;

  BaseApiClient(this.httpService, AppConfig config) : baseUrl = config.baseUrl;

  /// Performs a network request and handles all generic error mapping.
  ///
  /// This method centralizes all `try-catch` logic. It catches low-level
  /// exceptions and throws the appropriate, specific `ApiException`.
  @protected
  Future<T> performRequest<T>({
    required Future<http.Response> Function() request,
    required T Function(String body) parser,
    String resourceName = 'Resource',
  }) async {
    try {
      final response = await request();

      if (response.body.isEmpty) {
        // A non-nullable type expects a non-empty body.
        // `null is T` is a static check to see if the type `T` is nullable.
        if (null is T) {
          return null as T;
        }
        throw DataParsingException(
          "Response body was empty for $resourceName, but a non-nullable type was expected.",
        );
      }

      return parser(response.body);
    } on ClientNetworkException catch (e) {
      throw NetworkException(details: e.toString());
    } on HttpException catch (e) {
      throw _handleHttpException(e, resourceName: resourceName);
    } on FormatException catch (e) {
      throw DataParsingException("Bad JSON for $resourceName: ${e.message}");
    }
  }

  /// Multipart variant for file uploads.
  @protected
  Future<T> performMultipartRequest<T>({
    required Future<http.Response> Function() request,
    required T Function(String body) parser,
    String resourceName = 'Resource',
  }) async {
    try {
      final response = await request();

      if (response.body.isEmpty) {
        if (null is T) return null as T;
        throw DataParsingException(
          "Response body was empty for $resourceName, but a non-nullable type was expected.",
        );
      }

      return parser(response.body);
    } on ClientNetworkException catch (e) {
      throw NetworkException(details: e.toString());
    } on HttpException catch (e) {
      throw _handleHttpException(e, resourceName: resourceName);
    } on FormatException catch (e) {
      throw DataParsingException("Bad JSON for $resourceName: ${e.message}");
    }
  }

  @protected
  Future<T> performRawRequest<T>({
    required Future<http.Response> Function() request,
    required T Function(http.Response response) parser,
    String resourceName = 'Resource',
  }) async {
    try {
      final response = await request();
      return parser(response);
    } on ClientNetworkException catch (e) {
      throw NetworkException(details: e.toString());
    } on HttpException catch (e) {
      throw _handleHttpException(e, resourceName: resourceName);
    }
  }

  /// Maps raw `HttpException`s to specific `ApiException`s.
  ApiException _handleHttpException(
    HttpException e, {
    String resourceName = 'Resource',
  }) {
    HttpProblem? problem;
    try {
      final decodedBody = utf8.decode(e.response.bodyBytes);
      problem = HttpProblemMapper.fromJson(decodedBody);
    } catch (_) {
      // Ignore if the body is not a valid HttpProblem.
    }

    switch (e.response.statusCode) {
      case 401:
        if (e.requireAuth) {
          return SessionTerminatedException(problem: problem);
        }
        return CredentialsRejectedException(problem: problem);
      case 403:
        return ForbiddenException(problem: problem);
      case 404:
        return ResourceNotFoundException(resourceName, problem: problem);
      case 429:
        return RateLimitExceededException(problem: problem);
      case 400:
        if (problem is HttpValidationProblem) {
          return InvalidInputException(
            problem.detail ?? 'Invalid input for $resourceName.',
            validationProblem: problem,
          );
        }
        return InvalidInputException(
          problem?.detail ?? 'Invalid input provided for $resourceName.',
        );
      case int n when (n >= 500 && n < 600):
        return ServerUnavailableException(problem: problem);
      default:
        return ApiException(
          problem?.detail ??
              'Failed to load $resourceName: Status ${e.response.statusCode}',
          problem: problem,
        );
    }
  }
}
