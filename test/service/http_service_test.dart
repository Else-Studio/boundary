import 'dart:async';
import 'dart:convert';

import 'package:boundary/service/http_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/mockito.dart';

import '../helpers/mock_dependency_provider.dart';
import '../helpers/sut_factory.dart';
import '../helpers/mocks.mocks.dart';

// --- Test Plan: HttpService ---
//
// ## Group: Authentication and Client Selection
// - test('should use standard client when requireAuth is false')
//
// ## Group: Headers
// - test('sends only Accept on a GET without a body')
// - test('should merge custom headers with default headers, with custom taking precedence')
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
    });

    group('Headers', () {
      test('sends only Accept on a GET without a body', () async {
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
        expect(capturedHeaders, {'Accept': 'application/json'});
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
        expect(capturedHeaders, {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json',
        });
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
