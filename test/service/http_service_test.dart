import 'dart:async';
import 'dart:convert';

import 'package:boundary/service/auth_service.dart';
import 'package:boundary/service/http_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/mockito.dart';
import 'package:oauth2/oauth2.dart' as oauth2;

import '../helpers/mock_dependency_provider.dart';
import '../helpers/model_factory.dart';
import '../helpers/sut_factory.dart';
import '../helpers/mocks.mocks.dart';

// --- Test Plan: HttpService ---
//
// ## Group: Authentication and Client Selection
// - test('should use authenticated client and add auth headers when requireAuth is true')
// - test('should use standard client when requireAuth is false')
// - test('should throw NoSessionStored when requireAuth is true and user is not authenticated')
// - test('should attempt to refresh token when it is expired before making a request')
// - test('should throw SessionExpired when token refresh fails during a request')
//
// ## Group: Headers
// - test('should include default headers on all requests')
// - test('should merge custom headers with default headers, with custom taking precedence')
// - test('should set Accept-Language header correctly based on LocaleService')
//
// ## Group: Request-Specific Logic
// - test('should add Content-Type header when a body is present for a POST request')
//
// ## Group: General Error Handling
// - test('should throw ClientNetworkException on a TimeoutException')
// - test('should throw ClientNetworkException on a http.ClientException')
// - test('should throw HttpException on a non-2xx response')

void main() {
  late MockDependencyProvider provider;
  late HttpService httpService;
  late MockBaseClient mockHttpClient;

  setUp(() async {
    provider = MockDependencyProvider();
    // initTestBed must be called to set up shared_preferences for the SUT
    await SutFactory.initTestBed(provider: provider);
    httpService = SutFactory.createHttpService(provider: provider);
    mockHttpClient = provider.mockHttpClient;
  });

  group('HttpService', () {
    group('Authentication and Client Selection', () {
      test(
          'should use authenticated client and add auth headers when requireAuth is true',
          () async {
        // Arrange
        final mockAuthHttpClient = MockBaseClient();
        final credentials = ModelFactory.createCredentials();
        final authClient = oauth2.Client(
          credentials,
          httpClient: mockAuthHttpClient,
        );
        final testUrl = Uri.parse('https://api.example.com/data');

        when(provider.mockAuthService.client).thenReturn(authClient);
        when(mockAuthHttpClient.send(any)).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode('{}')),
            200,
          ),
        );

        // Act
        await httpService.get(testUrl, requireAuth: true);

        // Assert
        verifyNever(mockHttpClient.get(any, headers: anyNamed('headers')));
        final captured = verify(mockAuthHttpClient.send(captureAny)).captured;

        final capturedRequest = captured.single as http.Request;
        expect(
          capturedRequest.headers['Authorization'],
          'Bearer ${credentials.accessToken}',
        );
      });

      test('should use standard client when requireAuth is false', () async {
        // Arrange
        final testUrl = Uri.parse('https://api.example.com/data');
        when(mockHttpClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async => http.Response('{}', 200));

        // Act
        await httpService.get(testUrl, requireAuth: false);

        // Assert
        verify(mockHttpClient.get(testUrl, headers: anyNamed('headers')))
            .called(1);
      });

      test(
          'should throw NoSessionStored when requireAuth is true and user is not authenticated',
          () {
        // Arrange
        final testUrl = Uri.parse('https://api.example.com/data');
        when(provider.mockAuthService.authenticated).thenReturn(false);

        // Act
        final call = httpService.get(testUrl, requireAuth: true);

        // Assert
        expect(call, throwsA(isA<NoSessionStored>()));
      });

      test(
          'should attempt to refresh token when it is expired before making a request',
          () async {
        // Arrange
        final mockAuthHttpClient = MockBaseClient();
        final expiredCredentials = ModelFactory.createCredentials(
          expiration: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        final expiredAuthClient = oauth2.Client(
          expiredCredentials,
          httpClient: mockAuthHttpClient,
        );
        final refreshedCredentials = ModelFactory.createCredentials(
          accessToken: 'new-refreshed-token',
        );
        final refreshedAuthClient = oauth2.Client(
          refreshedCredentials,
          httpClient: mockAuthHttpClient,
        );
        final testUrl = Uri.parse('https://api.example.com/data');

        when(provider.mockAuthService.refreshCredentialsIfExpired())
            .thenAnswer((_) async {});
        when(provider.mockAuthService.client)
            .thenReturnInOrder([expiredAuthClient, refreshedAuthClient]);
        when(mockAuthHttpClient.send(any)).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode('{}')),
            200,
          ),
        );

        // Act
        await httpService.get(testUrl, requireAuth: true);

        // Assert
        verify(provider.mockAuthService.refreshCredentialsIfExpired())
            .called(1);

        final captured = verify(mockAuthHttpClient.send(captureAny)).captured;
        final capturedRequest = captured.single as http.Request;
        expect(
          capturedRequest.headers['Authorization'],
          'Bearer ${refreshedCredentials.accessToken}',
        );
      });

      test(
          'should throw HttpException 401 when token refresh fails during a request',
          () {
        // Arrange
        final mockAuthHttpClient = MockBaseClient();
        final expiredCredentials = ModelFactory.createCredentials(
          expiration: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        final expiredAuthClient = oauth2.Client(
          expiredCredentials,
          httpClient: mockAuthHttpClient,
        );
        final testUrl = Uri.parse('https://api.example.com/data');

        when(provider.mockAuthService.client).thenReturn(expiredAuthClient);
        when(provider.mockAuthService.refreshCredentialsIfExpired())
            .thenThrow(const SessionExpired(message: 'Refresh failed'));

        // Act
        final call = httpService.get(testUrl, requireAuth: true);

        // Assert
        expect(
            call,
            throwsA(isA<HttpException>()
                .having((e) => e.response.statusCode, 'statusCode', 401)));
      });
    });

    group('Headers', () {
      test('should include default headers on all requests', () async {
        // Arrange
        final testUrl = Uri.parse('https://api.example.com/data');
        when(mockHttpClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async => http.Response('{}', 200));

        // Act
        await httpService.get(testUrl, requireAuth: false);

        // Assert
        final captured =
            verify(mockHttpClient.get(any, headers: captureAnyNamed('headers')))
                .captured;
        final capturedHeaders = captured.single as Map<String, String>;
        expect(capturedHeaders['Accept'], 'application/json');
        expect(capturedHeaders.containsKey('Accept-Language'), isTrue);
        expect(capturedHeaders['Accept-Language'], isNotEmpty);
      });

      test(
          'should merge custom headers with default headers, with custom taking precedence',
          () async {
        // Arrange
        final testUrl = Uri.parse('https://api.example.com/data');
        final customHeaders = {
          'X-Custom': 'value',
          'Accept': 'application/xml'
        };
        when(mockHttpClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async => http.Response('{}', 200));

        // Act
        await httpService.get(testUrl,
            headers: customHeaders, requireAuth: false);

        // Assert
        final captured =
            verify(mockHttpClient.get(any, headers: captureAnyNamed('headers')))
                .captured;
        final capturedHeaders = captured.single as Map<String, String>;
        expect(capturedHeaders['X-Custom'], 'value');
        expect(capturedHeaders['Accept'], 'application/xml');
      });

      test('should set Accept-Language header correctly based on LocaleService',
          () {
        // Arrange
        // Act
        // Assert
      },
          skip:
              'Unimplemented: This test requires SutFactory.createHttpService to allow injecting a mock LocaleService.');
    });

    group('Request-Specific Logic', () {
      test(
          'should add Content-Type header when a body is present for a POST request',
          () async {
        // Arrange
        final testUrl = Uri.parse('https://api.example.com/data');
        final body = jsonEncode({'key': 'value'});
        when(mockHttpClient.post(any,
                headers: anyNamed('headers'), body: anyNamed('body')))
            .thenAnswer((_) async => http.Response('{}', 201));

        // Act
        await httpService.post(testUrl, body: body, requireAuth: false);

        // Assert
        final captured = verify(mockHttpClient.post(any,
                headers: captureAnyNamed('headers'), body: anyNamed('body')))
            .captured;
        final capturedHeaders = captured[0] as Map<String, String>;
        expect(
            capturedHeaders['Content-Type'], 'application/json; charset=UTF-8');
      });
    });

    group('General Error Handling', () {
      test('should throw ClientNetworkException on a TimeoutException', () {
        // Arrange
        final testUrl = Uri.parse('https://api.example.com/data');
        when(mockHttpClient.get(any, headers: anyNamed('headers')))
            .thenThrow(TimeoutException('Request timed out'));

        // Act
        final call = httpService.get(testUrl, requireAuth: false);

        // Assert
        expect(call, throwsA(isA<ClientNetworkException>()));
      });

      test('should throw ClientNetworkException on a http.ClientException', () {
        // Arrange
        final testUrl = Uri.parse('https://api.example.com/data');
        when(mockHttpClient.get(any, headers: anyNamed('headers')))
            .thenThrow(http.ClientException('Connection failed'));

        // Act
        final call = httpService.get(testUrl, requireAuth: false);

        // Assert
        expect(call, throwsA(isA<ClientNetworkException>()));
      });

      test('should throw HttpException on a non-2xx response', () {
        // Arrange
        final testUrl = Uri.parse('https://api.example.com/data');
        when(mockHttpClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async => http.Response('Not Found', 404));

        // Act
        final call = httpService.get(testUrl, requireAuth: false);

        // Assert
        expect(
            call,
            throwsA(isA<HttpException>()
                .having((e) => e.response.statusCode, 'statusCode', 404)));
      });
    });
  });
}
