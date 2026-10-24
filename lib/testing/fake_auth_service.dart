import 'package:rxdart/rxdart.dart';

import '../service/auth_service.dart';

/// A controllable [AuthService] and [AccessTokenProvider] for tests.
class FakeAuthService implements AuthService {
  FakeAuthService({
    AuthState initial = const AuthUnknown(),
    this.token,
  });

  /// What [accessToken] returns.
  String? token;

  /// Answers [refreshAfterUnauthorized]. Default (null): sign out with
  /// [SignedOutReason.expired], clear [token], return null.
  Future<String?> Function(String rejectedToken)? onUnauthorized;

  /// How often [initialize] was called.
  int get initializeCalls => throw UnimplementedError('not implemented');

  /// How often [signOut] was called.
  int get signOutCalls => throw UnimplementedError('not implemented');

  /// The tokens passed to [refreshAfterUnauthorized], in order.
  List<String> get rejectedTokens => throw UnimplementedError('not implemented');

  /// Sets [token] and emits [Authenticated] for [session].
  void signIn({
    AuthSession session = const AuthSession(subject: 'test-user'),
    String token = 'test-token',
  }) {
    throw UnimplementedError('not implemented');
  }

  /// Emits [state] as is.
  void emit(AuthState state) {
    throw UnimplementedError('not implemented');
  }

  @override
  ValueStream<AuthState> get authState =>
      throw UnimplementedError('not implemented');

  @override
  Future<String?> accessToken() => throw UnimplementedError('not implemented');

  @override
  Future<void> initialize() => throw UnimplementedError('not implemented');

  @override
  Future<String?> refreshAfterUnauthorized(String rejectedToken) =>
      throw UnimplementedError('not implemented');

  @override
  Future<void> signOut() => throw UnimplementedError('not implemented');

  @override
  void dispose() => throw UnimplementedError('not implemented');
}
