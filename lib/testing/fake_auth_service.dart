import 'package:rxdart/rxdart.dart';

import '../service/auth_service.dart';

/// A controllable [AuthService] and [AccessTokenProvider] for tests.
class FakeAuthService implements AuthService {
  FakeAuthService({
    AuthState initial = const AuthUnknown(),
    this.token,
  }) : _authState = BehaviorSubject<AuthState>.seeded(initial);

  final BehaviorSubject<AuthState> _authState;

  /// What [accessToken] returns.
  String? token;

  /// Answers [refreshAfterUnauthorized]. Default (null): sign out with
  /// [SignedOutReason.expired], clear [token], return null.
  Future<String?> Function(String rejectedToken)? onUnauthorized;

  int _initializeCalls = 0;
  int _signOutCalls = 0;
  final List<String> _rejectedTokens = [];

  /// How often [initialize] was called.
  int get initializeCalls => _initializeCalls;

  /// How often [signOut] was called.
  int get signOutCalls => _signOutCalls;

  /// The tokens passed to [refreshAfterUnauthorized], in order.
  List<String> get rejectedTokens => List.unmodifiable(_rejectedTokens);

  /// Sets [token] and emits [Authenticated] for [session].
  void signIn({
    AuthSession session = const AuthSession(subject: 'test-user'),
    String token = 'test-token',
  }) {
    this.token = token;
    emit(Authenticated(session));
  }

  /// Emits [state] as is.
  void emit(AuthState state) {
    if (_authState.isClosed) return;
    _authState.add(state);
  }

  @override
  ValueStream<AuthState> get authState => _authState.stream;

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<void> initialize() async {
    _initializeCalls++;
  }

  @override
  Future<String?> refreshAfterUnauthorized(String rejectedToken) async {
    _rejectedTokens.add(rejectedToken);
    final handler = onUnauthorized;
    if (handler != null) return handler(rejectedToken);

    token = null;
    emit(const SignedOut(SignedOutReason.expired));
    return null;
  }

  @override
  Future<void> signOut() async {
    _signOutCalls++;
    token = null;
    emit(const SignedOut(SignedOutReason.signedOut));
  }

  @override
  void dispose() {
    _authState.close();
  }
}
