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
// - test('a request carries the provider's bearer token')
// - test('a POST with a body carries the bearer token next to its content headers')
// - test('with no token nothing is sent and a 401 is thrown')
// - test('a 401 asks the provider to refresh and retries once with the new token')
// - test('a refresh that gives no token lets the 401 stand')
// - test('a second 401 is reported to the provider and not retried')
// - test('an unauthenticated request asks the provider for no token')
// - test('an unauthenticated 401 is thrown as an exception that needed no token')
// - test('a 429 is retried after retry-after')
// - test('a multipart upload is sent once even after a 401')
// - test('an error from accessToken reaches the caller')
// - test('an error from refreshAfterUnauthorized reaches the caller')
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

      group('bearer token', () {
        final url = Uri.parse('https://api.example.com/data');

        MockAuthService tokens() => provider.mockAuthService;

        /// Answers with each response in turn.
        Future<http.Response> Function(Invocation) inOrder(
            List<http.Response> responses) {
          var next = 0;
          return (_) async => responses[next++];
        }

        test('a request carries the provider\'s bearer token', () async {
          when(tokens().accessToken()).thenAnswer((_) async => 'tok-1');
          when(mockHttpClient.get(any, headers: anyNamed('headers')))
              .thenAnswer((_) async => http.Response('{}', 200));

          await httpService.get(url);

          final headers = verify(
                  mockHttpClient.get(any, headers: captureAnyNamed('headers')))
              .captured
              .single as Map<String, String>;
          expect(headers, {
            'Accept': 'application/json',
            'Authorization': 'Bearer tok-1',
          });
        });

        test(
            'a POST with a body carries the bearer token next to its content headers',
            () async {
          when(tokens().accessToken()).thenAnswer((_) async => 'tok-1');
          when(mockHttpClient.post(any,
                  headers: anyNamed('headers'), body: anyNamed('body')))
              .thenAnswer((_) async => http.Response('{}', 200));

          await httpService.post(url, body: '{"a":1}');

          final headers = verify(mockHttpClient.post(any,
                  headers: captureAnyNamed('headers'), body: anyNamed('body')))
              .captured
              .single as Map<String, String>;
          expect(headers, {
            'Content-Type': 'application/json; charset=UTF-8',
            'Accept': 'application/json',
            'Authorization': 'Bearer tok-1',
          });
        });

        test('with no token nothing is sent and a 401 is thrown', () async {
          when(tokens().accessToken()).thenAnswer((_) async => null);

          await expectLater(
            httpService.get(url),
            throwsA(isA<HttpException>()
                .having((e) => e.response.statusCode, 'statusCode', 401)
                .having((e) => e.requireAuth, 'requireAuth', true)),
          );

          verifyNever(mockHttpClient.get(any, headers: anyNamed('headers')));
        });

        test(
            'a 401 asks the provider to refresh and retries once with the new token',
            () async {
          when(tokens().accessToken()).thenAnswer((_) async => 'tok-1');
          when(tokens().refreshAfterUnauthorized('tok-1'))
              .thenAnswer((_) async => 'tok-2');
          when(mockHttpClient.get(any, headers: anyNamed('headers')))
              .thenAnswer(inOrder([
            http.Response('', 401),
            http.Response('{"ok":true}', 200),
          ]));

          final response = await httpService.get(url);

          expect(response.body, '{"ok":true}');
          final headers = verify(
                  mockHttpClient.get(any, headers: captureAnyNamed('headers')))
              .captured
              .cast<Map<String, String>>();
          expect(headers, hasLength(2));
          expect(headers.first['Authorization'], 'Bearer tok-1');
          expect(headers.last['Authorization'], 'Bearer tok-2');
          expect(
            verify(tokens().refreshAfterUnauthorized(captureAny)).captured,
            ['tok-1'],
          );
        });

        test('a refresh that gives no token lets the 401 stand', () async {
          when(tokens().accessToken()).thenAnswer((_) async => 'tok-1');
          when(tokens().refreshAfterUnauthorized('tok-1'))
              .thenAnswer((_) async => null);
          when(mockHttpClient.get(any, headers: anyNamed('headers')))
              .thenAnswer(
                  (_) async => http.Response('{"reason":"unauthorized"}', 401));

          await expectLater(
            httpService.get(url),
            throwsA(isA<HttpException>()
                .having(
                    (e) => e.response.body, 'body', '{"reason":"unauthorized"}')
                .having((e) => e.requireAuth, 'requireAuth', true)),
          );

          verify(mockHttpClient.get(any, headers: anyNamed('headers')))
              .called(1);
        });

        test('a second 401 is reported to the provider and not retried',
            () async {
          when(tokens().accessToken()).thenAnswer((_) async => 'tok-1');
          when(tokens().refreshAfterUnauthorized('tok-1'))
              .thenAnswer((_) async => 'tok-2');
          when(tokens().refreshAfterUnauthorized('tok-2'))
              .thenAnswer((_) async => null);
          when(mockHttpClient.get(any, headers: anyNamed('headers')))
              .thenAnswer((_) async => http.Response('', 401));

          await expectLater(
            httpService.get(url),
            throwsA(isA<HttpException>()
                .having((e) => e.response.statusCode, 'statusCode', 401)),
          );

          verify(mockHttpClient.get(any, headers: anyNamed('headers')))
              .called(2);
          expect(
            verify(tokens().refreshAfterUnauthorized(captureAny)).captured,
            ['tok-1', 'tok-2'],
          );
        });

        test('an unauthenticated request asks the provider for no token',
            () async {
          when(mockHttpClient.get(any, headers: anyNamed('headers')))
              .thenAnswer((_) async => http.Response('{}', 200));

          await httpService.get(url, requireAuth: false);

          verifyNever(tokens().accessToken());
          final headers = verify(
                  mockHttpClient.get(any, headers: captureAnyNamed('headers')))
              .captured
              .single as Map<String, String>;
          expect(headers, {'Accept': 'application/json'});
        });

        test(
            'an unauthenticated 401 is thrown as an exception that needed no token',
            () async {
          when(mockHttpClient.get(any, headers: anyNamed('headers')))
              .thenAnswer(
                  (_) async => http.Response('{"reason":"unauthorized"}', 401));

          await expectLater(
            httpService.get(url, requireAuth: false),
            throwsA(isA<HttpException>()
                .having((e) => e.response.statusCode, 'statusCode', 401)
                .having((e) => e.requireAuth, 'requireAuth', false)),
          );

          verifyNever(tokens().accessToken());
          verifyNever(tokens().refreshAfterUnauthorized(any));
        });

        test('a 429 is retried after retry-after', () async {
          when(mockHttpClient.get(any, headers: anyNamed('headers')))
              .thenAnswer(inOrder([
            http.Response('', 429, headers: {'retry-after': '0'}),
            http.Response('{}', 200),
          ]));

          final response = await httpService.get(url, requireAuth: false);

          expect(response.statusCode, 200);
          verify(mockHttpClient.get(any, headers: anyNamed('headers')))
              .called(2);
        });

        test('a multipart upload is sent once even after a 401', () async {
          when(tokens().accessToken()).thenAnswer((_) async => 'tok-1');
          when(tokens().refreshAfterUnauthorized('tok-1'))
              .thenAnswer((_) async => 'tok-2');
          when(mockHttpClient.send(any)).thenAnswer((_) async =>
              http.StreamedResponse(const Stream<List<int>>.empty(), 401));

          await expectLater(
            httpService.postMultipart(
              url,
              files: [http.MultipartFile.fromString('f', 'x')],
            ),
            throwsA(isA<HttpException>()
                .having((e) => e.response.statusCode, 'statusCode', 401)),
          );

          final sent = verify(mockHttpClient.send(captureAny)).captured;
          expect(sent, hasLength(1));
          expect((sent.single as http.BaseRequest).headers['Authorization'],
              'Bearer tok-1');
          expect(
            verify(tokens().refreshAfterUnauthorized(captureAny)).captured,
            ['tok-1'],
          );
        });

        test('an error from accessToken reaches the caller', () async {
          final error = StateError('locked');
          when(tokens().accessToken()).thenAnswer((_) async => throw error);

          await expectLater(httpService.get(url), throwsA(same(error)));

          verifyNever(mockHttpClient.get(any, headers: anyNamed('headers')));
        });

        test('an error from refreshAfterUnauthorized reaches the caller',
            () async {
          final error = StateError('locked');
          when(tokens().accessToken()).thenAnswer((_) async => 'tok-1');
          when(tokens().refreshAfterUnauthorized(any))
              .thenAnswer((_) async => throw error);
          when(mockHttpClient.get(any, headers: anyNamed('headers')))
              .thenAnswer((_) async => http.Response('', 401));

          await expectLater(httpService.get(url), throwsA(same(error)));

          verify(mockHttpClient.get(any, headers: anyNamed('headers')))
              .called(1);
        });
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
