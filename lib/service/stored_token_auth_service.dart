import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils.dart';

import 'auth_service.dart';

/// What the app's login call returns.
class TokenGrant {
  const TokenGrant({required this.token, this.subject});
  /// The access token sent as a bearer header.
  final String token;
  final String? subject; // becomes AuthSession.subject
}

/// Keeps one string. The app supplies a secure one (e.g. flutter_secure_storage).
abstract interface class CredentialStore {
  /// The stored value, or null.
  Future<String?> read();
  /// Stores [value], replacing any stored one.
  Future<void> write(String value);
  /// Removes the stored value.
  Future<void> delete();
}

/// NOT SECURE: SharedPreferences is plain storage (localStorage on web, a
/// plain file on devices). For development and tests; supply a secure
/// CredentialStore in production.
class SharedPreferencesCredentialStore implements CredentialStore {
  SharedPreferencesCredentialStore({this.key = 'boundary.credentials'});
  final String key;

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  @override
  Future<void> write(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  Future<void> delete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

/// An [AuthService] for a long-lived token with no refresh. The app supplies
/// the login call and a [CredentialStore]. A stored token means signed in at
/// start, with no network check; the first 401 signs out.
class StoredTokenAuthService<C> implements AuthService {
  StoredTokenAuthService({
    required Future<TokenGrant> Function(C credentials) login,
    required CredentialStore store,
    Future<void> Function(String token)? logout,
  })  : _login = login,
        _store = store,
        _logout = logout;

  final _logger = useLogger('TokA');
  final Future<TokenGrant> Function(C credentials) _login;
  final CredentialStore _store;
  final Future<void> Function(String token)? _logout;

  final _state$ = BehaviorSubject<AuthState>.seeded(const AuthUnknown());
  TokenGrant? _grant;
  bool _disposed = false;

  @override
  ValueStream<AuthState> get authState => _state$.stream;

  void _emit(AuthState state) {
    if (!_disposed) _state$.add(state);
  }

  /// Calls login; on success writes the store and emits Authenticated.
  /// On failure rethrows the login call's error; state and store unchanged.
  Future<void> signIn(C credentials) async {
    final grant = await _login(credentials);
    await _store.write(
      jsonEncode({'token': grant.token, 'subject': grant.subject}),
    );
    _grant = grant;
    _emit(Authenticated(AuthSession(subject: grant.subject)));
  }

  @override
  Future<void> initialize() async {
    String? raw;
    try {
      raw = await _store.read();
    } catch (e, s) {
      _logger.warning('Could not read the stored credentials', e, s);
      if (!_disposed) _emit(const SignedOut(SignedOutReason.noSession));
      return;
    }
    if (_disposed) return;
    if (raw == null) {
      _emit(const SignedOut(SignedOutReason.noSession));
      return;
    }
    final grant = _parse(raw);
    if (grant == null) {
      await _deleteQuietly();
      _emit(const SignedOut(SignedOutReason.noSession));
      return;
    }
    _grant = grant;
    _emit(Authenticated(AuthSession(subject: grant.subject)));
  }

  TokenGrant? _parse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final token = json['token'];
      final subject = json['subject'];
      if (token is! String || token.isEmpty) return null;
      if (subject != null && subject is! String) return null;
      return TokenGrant(token: token, subject: subject as String?);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteQuietly() async {
    try {
      await _store.delete();
    } catch (e, s) {
      _logger.warning('Could not delete the stored credentials', e, s);
    }
  }

  @override
  Future<void> signOut() async {
    final old = _grant;
    _grant = null;
    await _deleteQuietly();
    _emit(const SignedOut(SignedOutReason.signedOut));
    final logout = _logout;
    if (old != null && logout != null) {
      try {
        await logout(old.token);
      } catch (e, s) {
        _logger.warning('Server logout failed', e, s);
      }
    }
  }

  @override
  Future<String?> accessToken() async {
    if (_state$.value is AuthUnknown) {
      await _state$.firstWhere(
        (s) => s is! AuthUnknown,
        orElse: () => const SignedOut(SignedOutReason.noSession),
      );
    }
    return _grant?.token;
  }

  @override
  Future<String?> refreshAfterUnauthorized(String rejectedToken) async {
    final current = _grant;
    if (current == null) return null;
    if (current.token != rejectedToken) return current.token;
    _grant = null;
    await _deleteQuietly();
    _emit(const SignedOut(SignedOutReason.expired));
    return null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _state$.close();
  }
}
