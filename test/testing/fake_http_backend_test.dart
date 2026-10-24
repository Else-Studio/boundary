import 'package:boundary/boundary.dart';
import 'package:boundary/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sut_factory.dart';

void main() {
  /// An [HttpService] that talks to [backend] and signs in with a test token.
  HttpService serviceFor(FakeHttpBackend backend) {
    return SutFactory.createHttpService(
      tokens: SutFactory.createFakeAuthService()..signIn(),
      client: backend.client,
    );
  }

  test('answers a GET with an encoded body and records the request', () async {
    final backend = SutFactory.createFakeHttpBackend();
    backend.on('GET', '/cases', body: [
      {'id': 1},
    ]);
    final httpService = serviceFor(backend);

    final response =
        await httpService.get(Uri.parse('https://api.test/cases?page=2'));

    expect(response.statusCode, 200);
    expect(response.body, '[{"id":1}]');

    final request = backend.requests.single;
    expect(request.method, 'GET');
    expect(request.url, Uri.parse('https://api.test/cases?page=2'));
    expect(request.headers['Authorization'], 'Bearer test-token');
  });

  test('serves several answers for one key in order, repeating the last',
      () async {
    final backend = SutFactory.createFakeHttpBackend();
    backend.on('POST', '/notes', status: 500);
    backend.on('POST', '/notes', status: 201, body: '{}');
    final httpService = serviceFor(backend);
    final url = Uri.parse('https://api.test/notes');

    await expectLater(
      httpService.post(url, requireAuth: false),
      throwsA(
        isA<HttpException>()
            .having((e) => e.response.statusCode, 'statusCode', 500),
      ),
    );

    final second = await httpService.post(url, requireAuth: false);
    final third = await httpService.post(url, requireAuth: false);

    expect(second.statusCode, 201);
    expect(third.statusCode, 201);
    expect(backend.requests, hasLength(3));
  });

  test('an unexpected request fails with a 404 that names it', () async {
    final backend = SutFactory.createFakeHttpBackend();
    final httpService = serviceFor(backend);

    await expectLater(
      httpService.get(Uri.parse('https://api.test/nope'), requireAuth: false),
      throwsA(
        isA<HttpException>()
            .having((e) => e.response.statusCode, 'statusCode', 404)
            .having(
              (e) => e.response.body,
              'body',
              contains('No fake response for GET /nope'),
            ),
      ),
    );
  });
}
