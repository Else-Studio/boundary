# Auth

Boundary's auth is pluggable. The coordinator and `HttpService` depend on the `AuthService` interface only. Most apps use `StoredTokenAuthService`, which signs in with the app's own login call and keeps a long-lived token. This page covers the auth state, the stored-token service, the rule for 401 responses, and writing your own service.

## The auth state

`AuthService.authState` is a `ValueStream<AuthState>`:

| State | Meaning |
|---|---|
| `AuthUnknown()` | The service has not finished `initialize()`. Every service starts here. |
| `Authenticated(session)` | Signed in. `session` is an `AuthSession` with an optional `subject`, such as the user's email. |
| `SignedOut(reason)` | Not signed in. `reason` is `noSession` (nothing stored), `expired` (a 401 ended the session) or `signedOut` (the user signed out). |

The coordinator reacts to every change. You never navigate after a sign-in or sign-out:

| Change | What the coordinator shows |
|---|---|
| To `Authenticated` | The route saved before sign-in, or `getPostLoginDefaultRoute()`. A `guestOnly` route like login is left. |
| To `SignedOut(noSession)` or `SignedOut(expired)` on a protected route | The login route. The protected route is saved, so the user returns to it after signing in again. |
| To `SignedOut(signedOut)` on a protected route | The login route. Nothing is saved. |

A controller that needs the signed-in user takes the `AuthService` and reads `authState.value`, or follows it with `listenTo(auth.authState, ...)`. `AuthSession` carries only a subject. Keep the user's profile in your own service, or extend `AuthSession` in your own `AuthService`.

## The stored-token service

`StoredTokenAuthService<C>` is for a backend that returns a long-lived token at login and has no refresh. `C` is your credentials type. You supply the login call and a `CredentialStore`:

```dart
final auth = StoredTokenAuthService<LoginCredentials>(
  login: (credentials) => injector.get<AuthApi>().login(credentials),
  store: SharedPreferencesCredentialStore(), // not secure: see below
);
injector.addInstance<AuthService>(auth);
injector.addInstance<StoredTokenAuthService<LoginCredentials>>(auth);
```

Register it in `registerDependencies`. Register it twice: as `AuthService` for the coordinator and `HttpService`, and as its own type for the login controller, which calls `signIn`.

The login call reaches the API client through the injector when it runs, not when the service is built. The API client needs `HttpService`, `HttpService` needs the `AuthService`, and the late lookup breaks that cycle.

The login call returns a `TokenGrant(token: ..., subject: ...)`. The subject becomes `AuthSession.subject`. An optional `logout: (token) async { ... }` tells the server about a sign-out.

How it behaves:

| Event | Result |
|---|---|
| `initialize()` with a stored token | `Authenticated`. There is no network check: the first API call finds out whether the token still works. |
| `initialize()` with nothing stored, or an unreadable store | `SignedOut(noSession)` |
| `initialize()` with a stored value it cannot parse | Deletes it. `SignedOut(noSession)` |
| `signIn(credentials)` succeeds | Writes the token to the store. `Authenticated` |
| `signIn` fails, in the login call or in the store write | Rethrows the error. The state and the store are unchanged. |
| `signOut()` | Deletes the token. `SignedOut(signedOut)`. Then calls `logout`, if given. Failures of the delete or of `logout` are logged and do not stop the sign-out. |
| A 401 for the current token | Deletes the token. `SignedOut(expired)`. |
| `accessToken()` while the state is unknown | Waits until `initialize()` has finished. |

### The login controller

The controller calls `signIn`, shows a refused sign-in inline, and does not navigate:

```dart
try {
  await _auth.signIn(LoginCredentials(
    email: form.control(LoginFormKeys.email).value as String,
    password: form.control(LoginFormKeys.password).value as String,
  ));
  // No navigateTo: the coordinator sees Authenticated and leaves
  // the guest-only login route by itself.
} on CredentialsRejectedException catch (e) {
  emit(_error, _errors.messageFor(e));
} finally {
  emit(_busy, false);
}
```

A refused password must arrive as `CredentialsRejectedException`. It does when the login call goes through `HttpService` with `requireAuth: false` and the server answers 401. See [api_client.md](api_client.md).

Sign out from any controller with `await auth.signOut()`.

### Storing the token safely

`SharedPreferencesCredentialStore` keeps the token in plain storage: a plain file on devices, and `localStorage` on the web. It is **not secure**. Use it for development and tests only.

In production, implement `CredentialStore` with secure storage. With the `flutter_secure_storage` package, which your app adds, it is three methods:

```dart
class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore(this._storage);

  final FlutterSecureStorage _storage;
  static const _key = 'credentials';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
```

## Tokens and 401 responses

`HttpService` asks the auth service for tokens through the `AccessTokenProvider` part of the interface. Every request sent with `requireAuth: true`, the default, follows these rules:

- **No token:** `HttpService` throws a 401 `HttpException` without sending anything.
- **A 401 response:** it calls `refreshAfterUnauthorized(token)`. If that returns a new token, it retries the request once. If it returns null, it throws the 401.
- **A second 401** in the same call is also reported to `refreshAfterUnauthorized` and then thrown, never retried. A provider that cannot refresh has therefore signed out before your code sees the error.
- A multipart upload is sent once, with no 401 retry.

`BaseApiClient` turns a 401 on such a call into `SessionTerminatedException`. The error policy ignores it, because the user is already being signed out.

A request sent with `requireAuth: false` carries no token. A 401 on it means the server refused what was sent, such as a wrong password, and becomes `CredentialsRejectedException`.

## Writing your own auth service

Implement `AuthService` when your backend needs something else, such as tokens that refresh. Keep to these rules, because the coordinator and `HttpService` rely on them:

- `authState` starts at `AuthUnknown`.
- `initialize()` is called once by the coordinator. It ends in `Authenticated` or `SignedOut`.
- `signOut()` clears the session locally and ends in `SignedOut(SignedOutReason.signedOut)`, even when a server call fails.
- `accessToken()` returns the current token, or null when there is none.
- `refreshAfterUnauthorized(rejectedToken)` returns a new token to retry with, or signs out with `SignedOut(SignedOutReason.expired)` and returns null. If the rejected token is older than the current one, return the current one.
- `dispose()` closes the stream.

## Web OAuth (deprecated)

`package:boundary/oauth.dart` holds `OAuthAuthService`, a web-only OAuth2 PKCE service configured with `OAuthConfig`, and `SharedPreferencesPostAuthRedirectStore`, which keeps the saved route across the sign-in redirect for five minutes. It is deprecated and kept for reference. New apps use `StoredTokenAuthService` or their own `AuthService`.

## Testing

`FakeAuthService` from `package:boundary/testing.dart` lets a test set the auth state and the token, and records sign-outs and 401 reports. See [testing.md](testing.md).
