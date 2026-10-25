import 'package:boundary/boundary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/mock_dependency_provider.dart';
import '../helpers/sut_factory.dart';

class _TestConfig implements AppConfig {
  @override
  String get baseUrl => 'https://api.example.com';

  @override
  Duration get debounceTime => Duration.zero;
}

class _TestApiClient extends BaseApiClient {
  _TestApiClient(super.httpService, super.config);

  Future<String> run(Future<http.Response> Function() request) {
    return performRequest<String>(
      request: request,
      parser: (body) => body,
    );
  }

  Future<String> runMultipart(Future<http.Response> Function() request) {
    return performMultipartRequest<String>(
      request: request,
      parser: (body) => body,
    );
  }

  Future<http.Response> runRaw(Future<http.Response> Function() request) {
    return performRawRequest<http.Response>(
      request: request,
      parser: (response) => response,
    );
  }
}

void main() {
  late MockDependencyProvider provider;
  late _TestApiClient client;

  setUp(() async {
    provider = MockDependencyProvider();
    await SutFactory.initTestBed(provider: provider);
    client = _TestApiClient(
      SutFactory.createHttpService(provider: provider),
      _TestConfig(),
    );
  });

  test('a 401 on a call that needed a token keeps the problem reason', () async {
    try {
      await client.run(
        () async => throw HttpException(
          http.Response('{"reason":"unauthorized"}', 401),
          requireAuth: true,
        ),
      );
      fail('expected SessionTerminatedException');
    } on SessionTerminatedException catch (e) {
      expect(e.problem!.extensions['reason'], 'unauthorized');
    }
  });

  test(
      'a 401 on a call that needed no token is a refused sign-in', () async {
    try {
      await client.run(
        () async => throw HttpException(
          http.Response('{"reason":"unauthorized"}', 401),
        ),
      );
      fail('expected CredentialsRejectedException');
    } on CredentialsRejectedException catch (e) {
      expect(e, isNot(isA<SessionTerminatedException>()));
      expect(e.message, 'The sign-in details were not accepted.');
      expect(e.problem!.extensions['reason'], 'unauthorized');
    } on SessionTerminatedException catch (e) {
      fail(
        'expected CredentialsRejectedException, '
        'got SessionTerminatedException(${e.message})',
      );
    }
  });

  test('a multipart request maps a 404 to a missing resource', () async {
    await expectLater(
      client.runMultipart(
        () async => throw HttpException(http.Response('', 404)),
      ),
      throwsA(isA<ResourceNotFoundException>()),
    );
  });

  test('a raw request maps a 404 to a missing resource', () async {
    await expectLater(
      client.runRaw(
        () async => throw HttpException(http.Response('', 404)),
      ),
      throwsA(isA<ResourceNotFoundException>()),
    );
  });

  test('a raw request does not turn a parse failure into a parsing error',
      () async {
    Future<http.Response> failing() async =>
        throw const FormatException('not json');

    await expectLater(
      client.run(failing),
      throwsA(isA<DataParsingException>()),
    );
    await expectLater(
      client.runRaw(failing),
      throwsA(isA<FormatException>()),
    );
  });
}
