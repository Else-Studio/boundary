import 'package:rxdart/rxdart.dart';

/// Who is signed in. Apps may extend it to carry more.
class AuthSession {
  const AuthSession({this.subject});

  /// A stable user id or login name, when known.
  final String? subject;
}

enum SignedOutReason { noSession, expired, signedOut }

sealed class AuthState {
  const AuthState();
}

/// Before initialize() has settled.
final class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// == when the sessions are identical.
final class Authenticated extends AuthState {
  const Authenticated(this.session);
  final AuthSession session;
}

/// == when the reasons are equal.
final class SignedOut extends AuthState {
  const SignedOut(this.reason);
  final SignedOutReason reason;
}

abstract interface class AccessTokenProvider {
  /// The current access token, or null when there is none.
  Future<String?> accessToken();

  /// Called by HttpService after every 401 for [rejectedToken], including a
  /// 401 for the token this method just returned. Returns a token to retry
  /// with, or null. HttpService retries at most once per call, so its answer
  /// to a second 401 is not used. A provider that cannot refresh signs out
  /// here.
  Future<String?> refreshAfterUnauthorized(String rejectedToken);
}

abstract interface class AuthService implements AccessTokenProvider {
  /// Starts at AuthUnknown.
  ValueStream<AuthState> get authState;

  /// Reads the stored session. Called once by AppCoordinator.
  Future<void> initialize();

  /// Clears the session locally and ends in SignedOut(signedOut).
  Future<void> signOut();

  void dispose();
}
