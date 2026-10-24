import 'package:boundary/boundary.dart';
import 'package:boundary/testing.dart';
import 'package:flutter_test/flutter_test.dart' hide pumpEventQueue;

import '../helpers/model_factory.dart';
import '../helpers/sut_factory.dart';

void main() {
  group('state', () {
    test('a new fake auth service is unknown', () {
      final FakeAuthService auth = SutFactory.createFakeAuthService();

      expect(auth.authState.value, const AuthUnknown());
    });

    test('signing in sets the test session and token', () async {
      final auth = SutFactory.createFakeAuthService();

      auth.signIn();

      final state = auth.authState.value;
      expect(state, isA<Authenticated>());
      expect((state as Authenticated).session.subject, 'test-user');
      expect(await auth.accessToken(), 'test-token');
    });

    test('signing out clears the token and reports the signed-out reason',
        () async {
      final auth = SutFactory.createFakeAuthService()..signIn();

      await auth.signOut();

      expect(auth.authState.value, const SignedOut(SignedOutReason.signedOut));
      expect(await auth.accessToken(), isNull);
      expect(auth.signOutCalls, 1);
    });

    test('initializing only counts and leaves the state alone', () async {
      final auth = SutFactory.createFakeAuthService();

      await auth.initialize();
      await auth.initialize();

      expect(auth.initializeCalls, 2);
      expect(auth.authState.value, const AuthUnknown());
    });

    test('emitting a state sets it as is', () {
      final auth = SutFactory.createFakeAuthService();
      final session = ModelFactory.createSession(subject: 'someone');

      auth.emit(Authenticated(session));

      expect(auth.authState.value, Authenticated(session));
    });

    test('disposing closes the auth state stream', () async {
      final auth = SutFactory.createFakeAuthService();
      var closed = false;
      auth.authState.listen(null, onDone: () => closed = true);

      auth.dispose();
      await pumpEventQueue();

      expect(closed, isTrue);
    });
  });

  group('unauthorized', () {
    test('by default a rejected token signs the fake out', () async {
      final auth = SutFactory.createFakeAuthService()..signIn();

      final replacement = await auth.refreshAfterUnauthorized('test-token');

      expect(replacement, isNull);
      expect(auth.authState.value, const SignedOut(SignedOutReason.expired));
      expect(await auth.accessToken(), isNull);
      expect(auth.rejectedTokens, ['test-token']);
    });

    test('a custom handler can answer with a new token and stays signed in',
        () async {
      final auth = SutFactory.createFakeAuthService()..signIn();
      auth.onUnauthorized = (_) async => 'tok-2';

      final replacement = await auth.refreshAfterUnauthorized('test-token');

      expect(replacement, 'tok-2');
      expect(auth.authState.value, isA<Authenticated>());
    });
  });
}
