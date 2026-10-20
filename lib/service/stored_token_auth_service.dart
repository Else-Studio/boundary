import 'package:rxdart/rxdart.dart';

import 'auth_service.dart';

/// What the app's login call returns.
class TokenGrant {
  const TokenGrant({required this.token, this.subject});
  final String token;
  final String? subject;
}

/// Keeps one string. The app supplies a secure one.
abstract interface class CredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// NOT SECURE: SharedPreferences is plain storage. For development and tests.
class SharedPreferencesCredentialStore implements CredentialStore {
  SharedPreferencesCredentialStore({this.key = 'boundary.credentials'});
  final String key;

  @override
  Future<String?> read() => throw UnimplementedError('not implemented');

  @override
  Future<void> write(String value) =>
      throw UnimplementedError('not implemented');

  @override
  Future<void> delete() => throw UnimplementedError('not implemented');
}

class StoredTokenAuthService<C> implements AuthService {
  StoredTokenAuthService({
    required Future<TokenGrant> Function(C credentials) login,
    required CredentialStore store,
    Future<void> Function(String token)? logout,
  });

  Future<void> signIn(C credentials) =>
      throw UnimplementedError('not implemented');

  @override
  ValueStream<AuthState> get authState =>
      throw UnimplementedError('not implemented');

  @override
  Future<void> initialize() => throw UnimplementedError('not implemented');

  @override
  Future<void> signOut() => throw UnimplementedError('not implemented');

  @override
  Future<String?> accessToken() => throw UnimplementedError('not implemented');

  @override
  Future<String?> refreshAfterUnauthorized(String rejectedToken) =>
      throw UnimplementedError('not implemented');

  @override
  void dispose() => throw UnimplementedError('not implemented');
}
