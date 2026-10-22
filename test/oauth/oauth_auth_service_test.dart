// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:boundary/oauth.dart';
import 'package:boundary/service/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/sut_factory.dart';

class FakeVerifier implements TokenVerifier {
  FakeVerifier({this.claims, this.error});

  Map<String, dynamic>? claims;
  Object? error;

  @override
  Future<Map<String, dynamic>> verify(String accessToken) async {
    if (error != null) throw error!;
    return claims ?? {'email': 'ada@example.com'};
  }
}

const _tokenResponseBody =
    '{"access_token":"tok-2","token_type":"bearer","expires_in":3600,'
    '"refresh_token":"ref-2","id_token":"id-2"}';

final _config = OAuthConfig(
  clientId: 'web-app',
  scopes: const ['openid', 'email'],
  authorizationEndpoint: Uri.parse('https://id.example.com/auth?hint=x'),
  tokenEndpoint: Uri.parse('https://id.example.com/token'),
  jwksEndpoint: Uri.parse('https://id.example.com/certs'),
  logoutEndpoint: Uri.parse('https://id.example.com/logout'),
  redirectUrl: Uri.parse('https://app.example.com/callback'),
  postLogoutRedirectUrl: Uri.parse('https://app.example.com/bye'),
  extraAuthorizationParameters: const {'embedded': 'true'},
);

String _credentialsJson({
  required String accessToken,
  String refreshToken = 'ref-1',
  String idToken = 'id-1',
  DateTime? expiration,
}) {
  return oauth2.Credentials(
    accessToken,
    refreshToken: refreshToken,
    idToken: idToken,
    tokenEndpoint: _config.tokenEndpoint,
    expiration: expiration ?? DateTime.now().add(const Duration(hours: 1)),
  ).toJson();
}

void main() {
  late List<http.BaseRequest> tokenRequests;
  late Completer<void>? tokenGate;
  late int tokenStatusCode;
  late String tokenBody;
  late FakeVerifier verifier;
  OAuthAuthService? service;

  MockClient buildClient() {
    return MockClient((request) async {
      tokenRequests.add(request);
      final gate = tokenGate;
      if (gate != null) await gate.future;
      return http.Response(
        tokenBody,
        tokenStatusCode,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    });
  }

  OAuthAuthService build() {
    return service = SutFactory.createOAuthAuthService(
      config: _config,
      httpClient: buildClient(),
      verifier: verifier,
    );
  }

  Future<OAuthAuthService> signedIn({
    String accessToken = 'tok-1',
    DateTime? expiration,
  }) async {
    SharedPreferences.setMockInitialValues({
      'oauth_credentials': _credentialsJson(
        accessToken: accessToken,
        expiration: expiration ?? DateTime.now().add(const Duration(hours: 1)),
      ),
    });
    final s = build();
    await s.initialize();
    tokenRequests.clear();
    return s;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tokenRequests = [];
    tokenGate = null;
    tokenStatusCode = 200;
    tokenBody = _tokenResponseBody;
    verifier = FakeVerifier();
    service = null;
  });

  tearDown(() {
    try {
      service?.dispose();
    } catch (_) {}
  });

  test('the authorize URL comes from the config', () async {
    final s = build();

    final url = await s.authorizationUrl();

    expect(
      url.replace(queryParameters: const {}).toString(),
      'https://id.example.com/auth',
    );
    final q = url.queryParameters;
    expect(q['client_id'], 'web-app');
    expect(q['redirect_uri'], 'https://app.example.com/callback');
    expect(q['response_type'], 'code');
    expect(q['code_challenge_method'], 'S256');
    expect(q['scope'], 'openid email');
    expect(q['hint'], 'x');
    expect(q['embedded'], 'true');
    expect(q['state'], isNotEmpty);
    expect(q['code_challenge'], isNotEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('authState'), q['state']);
    expect(prefs.getString('codeVerifier')!.length, 128);
  });

  test('stored valid credentials sign in without a token request', () async {
    SharedPreferences.setMockInitialValues({
      'oauth_credentials': _credentialsJson(accessToken: 'tok-1'),
    });
    final s = build();

    await s.initialize();

    final state = s.authState.value;
    expect(state, isA<Authenticated>());
    expect((state as Authenticated).session.subject, 'ada@example.com');
    expect(await s.accessToken(), 'tok-1');
    expect(tokenRequests, isEmpty);
  });

  test('a token that fails verification signs out as expired', () async {
    verifier = FakeVerifier(error: StateError('bad token'));
    SharedPreferences.setMockInitialValues({
      'oauth_credentials': _credentialsJson(accessToken: 'tok-1'),
    });
    final s = build();

    await s.initialize();

    expect(s.authState.value, const SignedOut(SignedOutReason.expired));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('oauth_credentials'), isFalse);
  });

  test('nothing stored means no session', () async {
    final s = build();

    await s.initialize();

    expect(s.authState.value, const SignedOut(SignedOutReason.noSession));
  });

  test('expired credentials are refreshed at start', () async {
    SharedPreferences.setMockInitialValues({
      'oauth_credentials': _credentialsJson(
        accessToken: 'tok-1',
        expiration: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    });
    final s = build();

    await s.initialize();

    expect(tokenRequests, hasLength(1));
    final body = tokenRequests.single as http.Request;
    expect(body.bodyFields['grant_type'], 'refresh_token');
    expect(body.bodyFields['refresh_token'], 'ref-1');
    final state = s.authState.value;
    expect(state, isA<Authenticated>());
    expect((state as Authenticated).session.subject, 'ada@example.com');
    expect(await s.accessToken(), 'tok-2');
  });

  test('the redirect exchanges the code', () async {
    SharedPreferences.setMockInitialValues({
      'codeVerifier': 'v' * 128,
      'authState': 's1',
    });
    final s = build();

    await s.handleRedirect({'code': 'c1', 'state': 's1'});

    expect(tokenRequests, hasLength(1));
    final body = tokenRequests.single as http.Request;
    expect(body.bodyFields['grant_type'], 'authorization_code');
    expect(body.bodyFields['code'], 'c1');
    expect(body.bodyFields['code_verifier'], 'v' * 128);
    final state = s.authState.value;
    expect(state, isA<Authenticated>());
    expect((state as Authenticated).session.subject, 'ada@example.com');
    final prefs = await SharedPreferences.getInstance();
    final saved = oauth2.Credentials.fromJson(
      prefs.getString('oauth_credentials')!,
    );
    expect(saved.accessToken, 'tok-2');
    expect(saved.refreshToken, 'ref-2');
    expect(saved.idToken, 'id-2');
    expect(prefs.containsKey('codeVerifier'), isFalse);
    expect(prefs.containsKey('authState'), isFalse);
  });

  test('a redirect with the wrong state fails cleanly', () async {
    SharedPreferences.setMockInitialValues({
      'codeVerifier': 'v' * 128,
      'authState': 's1',
    });
    final s = build();

    await expectLater(
      Future<void>.sync(
          () => s.handleRedirect({'code': 'c1', 'state': 'other'})),
      throwsA(anything),
    );

    expect(s.authState.value, const SignedOut(SignedOutReason.noSession));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('codeVerifier'), isFalse);
    expect(prefs.containsKey('authState'), isFalse);
    expect(tokenRequests, isEmpty);
  });

  test('a 401 refreshes once for concurrent callers', () async {
    final s = await signedIn();
    tokenGate = Completer<void>();

    final first = s.refreshAfterUnauthorized('tok-1');
    final second = s.refreshAfterUnauthorized('tok-1');
    await Future<void>.delayed(Duration.zero);
    tokenGate!.complete();

    expect(await first, 'tok-2');
    expect(await second, 'tok-2');
    expect(tokenRequests, hasLength(1));
  });

  test('a newer token from another tab is adopted', () async {
    final s = await signedIn();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'oauth_credentials',
      _credentialsJson(accessToken: 'tok-9'),
    );

    final result = await s.refreshAfterUnauthorized('tok-1');

    expect(result, 'tok-9');
    expect(tokenRequests, isEmpty);
  });

  test('a failed refresh signs out as expired', () async {
    final s = await signedIn();
    tokenStatusCode = 400;
    tokenBody = '{"error":"invalid_grant"}';

    final result = await s.refreshAfterUnauthorized('tok-1');

    expect(result, isNull);
    expect(s.authState.value, const SignedOut(SignedOutReason.expired));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('oauth_credentials'), isFalse);
  });

  test('logout URL then sign-out clears credentials', () async {
    final s = await signedIn();

    final url = await s.logoutUrl();
    expect(
      url.replace(queryParameters: const {}).toString(),
      'https://id.example.com/logout',
    );
    final q = url.queryParameters;
    expect(q['id_token_hint'], 'id-1');
    expect(q['post_logout_redirect_uri'], 'https://app.example.com/bye');
    expect(q['client_id'], 'web-app');

    await s.signOut();

    expect(s.authState.value, const SignedOut(SignedOutReason.signedOut));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('oauth_credentials'), isFalse);
  });

  test('a 401 for a token already replaced does not refresh again', () async {
    final s = await signedIn();

    final first = await s.refreshAfterUnauthorized('tok-1');
    expect(first, 'tok-2');
    expect(tokenRequests, hasLength(1));

    final second = await s.refreshAfterUnauthorized('tok-1');
    expect(second, 'tok-2');
    expect(tokenRequests, hasLength(1));
    expect(s.authState.value, isA<Authenticated>());
  });
}
