import 'dart:async';

import 'package:boundary/boundary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/sut_factory.dart';

typedef _Credentials = ({String email, String password});

const _ada = (email: 'ada@example.com', password: 'pw');
const _adaJson = '{"token":"tok-1","subject":"ada@example.com"}';

class MemoryStore implements CredentialStore {
  MemoryStore([this.value]);

  String? value;
  final writes = <String>[];
  int deletes = 0;
  Object? readError;
  Object? writeError;
  Object? deleteError;
  Completer<String?>? readGate;

  @override
  Future<String?> read() async {
    if (readError != null) throw readError!;
    if (readGate != null) return readGate!.future;
    return value;
  }

  @override
  Future<void> write(String v) async {
    writes.add(v);
    if (writeError != null) throw writeError!;
    value = v;
  }

  @override
  Future<void> delete() async {
    deletes++;
    if (deleteError != null) throw deleteError!;
    value = null;
  }
}

void main() {
  late MemoryStore store;
  late List<_Credentials> loginCalls;
  late Object? loginError;
  late String loginToken;
  late List<(String, AuthState)> logoutCalls;
  late List<int> deletesSeenByLogout;
  late Object? logoutError;
  StoredTokenAuthService<_Credentials>? service;

  StoredTokenAuthService<_Credentials> build({bool withLogout = false}) {
    return service = SutFactory.createStoredTokenAuthService<_Credentials>(
      login: (c) async {
        loginCalls.add(c);
        if (loginError != null) throw loginError!;
        return TokenGrant(token: loginToken, subject: c.email);
      },
      store: store,
      logout: withLogout
          ? (token) async {
              logoutCalls.add((token, service!.authState.value));
              deletesSeenByLogout.add(store.deletes);
              if (logoutError != null) throw logoutError!;
            }
          : null,
    );
  }

  setUp(() {
    store = MemoryStore();
    loginCalls = [];
    loginError = null;
    loginToken = 'tok-1';
    logoutCalls = [];
    deletesSeenByLogout = [];
    logoutError = null;
    service = null;
  });

  tearDown(() => service?.dispose());

  Future<StoredTokenAuthService<_Credentials>> signedIn(
    String token, {
    bool withLogout = false,
  }) async {
    store.value = '{"token":"$token","subject":"ada@example.com"}';
    final s = build(withLogout: withLogout);
    await s.initialize();
    store.writes.clear();
    return s;
  }

  test('a stored token signs in at start without calling login', () async {
    store.value = _adaJson;
    final s = build();
    expect(s.authState.value, isA<AuthUnknown>());

    await s.initialize();

    final state = s.authState.value;
    expect(state, isA<Authenticated>());
    expect((state as Authenticated).session.subject, 'ada@example.com');
    expect(await s.accessToken(), 'tok-1');
    expect(loginCalls, isEmpty);
  });

  test('nothing stored means no session', () async {
    final s = build();

    await s.initialize();

    expect(s.authState.value, const SignedOut(SignedOutReason.noSession));
    expect(await s.accessToken(), isNull);
  });

  test('a stored value that is not json is deleted', () async {
    store.value = 'not json';
    final s = build();

    await s.initialize();

    expect(s.authState.value, const SignedOut(SignedOutReason.noSession));
    expect(store.deletes, 1);
  });

  test('a stored value without a token is deleted', () async {
    store.value = '{"subject":"ada@example.com"}';
    final s = build();

    await s.initialize();

    expect(s.authState.value, const SignedOut(SignedOutReason.noSession));
    expect(store.deletes, 1);
  });

  test('a store that cannot be read means no session', () async {
    store.readError = StateError('keychain locked');
    final s = build();

    await s.initialize();

    expect(s.authState.value, const SignedOut(SignedOutReason.noSession));
  });

  test('signing in stores the token and emits the session', () async {
    final s = build();
    await s.initialize();

    await s.signIn(_ada);

    expect(loginCalls, [_ada]);
    expect(store.writes, [_adaJson]);
    final state = s.authState.value;
    expect(state, isA<Authenticated>());
    expect((state as Authenticated).session.subject, 'ada@example.com');
    expect(await s.accessToken(), 'tok-1');
  });

  test('a failed sign-in rethrows and changes nothing', () async {
    final error = InvalidInputException('bad password');
    loginError = error;
    final s = build();
    await s.initialize();

    await expectLater(s.signIn(_ada), throwsA(same(error)));

    expect(s.authState.value, const SignedOut(SignedOutReason.noSession));
    expect(store.writes, isEmpty);
  });

  test('the first 401 for the current token signs out as expired', () async {
    final s = await signedIn('tok-1');

    final result = await s.refreshAfterUnauthorized('tok-1');

    expect(result, isNull);
    expect(s.authState.value, const SignedOut(SignedOutReason.expired));
    expect(store.deletes, 1);
    expect(await s.accessToken(), isNull);
  });

  test('a 401 for an old token keeps a newer session', () async {
    final s = await signedIn('tok-2');

    final result = await s.refreshAfterUnauthorized('tok-1');

    expect(result, 'tok-2');
    expect(s.authState.value, isA<Authenticated>());
    expect(store.deletes, 0);
  });

  test('signing out clears the store first, then calls the server hook',
      () async {
    final s = await signedIn('tok-1', withLogout: true);

    await s.signOut();

    expect(store.deletes, 1);
    expect(s.authState.value, const SignedOut(SignedOutReason.signedOut));
    expect(logoutCalls, hasLength(1));
    expect(logoutCalls.single.$1, 'tok-1');
    expect(logoutCalls.single.$2, const SignedOut(SignedOutReason.signedOut));
    expect(deletesSeenByLogout, [1]);
  });

  test('a failing server logout still signs out', () async {
    logoutError = NetworkException();
    final s = await signedIn('tok-1', withLogout: true);

    await s.signOut();

    expect(s.authState.value, const SignedOut(SignedOutReason.signedOut));
  });

  test('the token waits for start-up to finish', () async {
    store.readGate = Completer<String?>();
    final s = build();
    final init = s.initialize();

    final token = s.accessToken();
    store.readGate!.complete('{"token":"tok-1","subject":null}');
    await init;

    expect(await token, 'tok-1');
  });

  test('a token waiting for start-up gives null when disposed', () async {
    store.readGate = Completer<String?>();
    final s = build();
    final init = s.initialize();

    final token = s.accessToken();
    s.dispose();
    service = null;
    store.readGate!.complete('{"token":"tok-1","subject":null}');
    await init;

    expect(await token, isNull);
  });

  test('a store that cannot delete still signs out', () async {
    final s = await signedIn('tok-1');
    store.deleteError = StateError('keychain locked');

    await s.signOut();

    expect(s.authState.value, const SignedOut(SignedOutReason.signedOut));
    expect(await s.accessToken(), isNull);
  });

  test('a store that cannot delete still ends the session on a 401', () async {
    final s = await signedIn('tok-1');
    store.deleteError = StateError('keychain locked');

    final result = await s.refreshAfterUnauthorized('tok-1');

    expect(result, isNull);
    expect(s.authState.value, const SignedOut(SignedOutReason.expired));
  });

  test('a sign-in that cannot be stored fails and changes nothing', () async {
    final error = StateError('disk full');
    store.writeError = error;
    final s = build();
    await s.initialize();

    await expectLater(s.signIn(_ada), throwsA(same(error)));

    expect(s.authState.value, const SignedOut(SignedOutReason.noSession));
    expect(await s.accessToken(), isNull);
  });

  group('SharedPreferencesCredentialStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('keeps one string under its key until deleted', () async {
      final prefsStore = SharedPreferencesCredentialStore();
      expect(await prefsStore.read(), isNull);

      await prefsStore.write('x');

      expect(await prefsStore.read(), 'x');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('boundary.credentials'), 'x');

      await prefsStore.delete();

      expect(await prefsStore.read(), isNull);
    });
  });
}
