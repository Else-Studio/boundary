import 'dart:math' show Random;

import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../service/auth_service.dart';
import '../utils.dart';
import 'oauth_config.dart';
import 'token_verifier.dart';

const String _prefsKeyCredentials = 'oauth_credentials';
const String _prefsKeyCodeVerifier = 'codeVerifier';
const String _prefsKeyState = 'authState';

const String _charset =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// Web-only OAuth2 PKCE adapter kept for reference.
@Deprecated(
    'Web-only OAuth kept for reference. New apps use StoredTokenAuthService.')
class OAuthAuthService implements AuthService {
  OAuthAuthService(
    OAuthConfig config, {
    http.Client? httpClient,
    TokenVerifier? verifier,
  })  : _config = config,
        _httpClient = httpClient ?? http.Client(),
        _verifier = verifier ?? JwksTokenVerifier(config.jwksEndpoint);

  final OAuthConfig _config;
  final http.Client _httpClient;
  final TokenVerifier _verifier;
  final _logger = useLogger('OAuS');

  final _state$ = BehaviorSubject<AuthState>.seeded(const AuthUnknown());
  oauth2.Credentials? _credentials;
  SharedPreferences? _prefs;
  Future<void>? _refreshTask;
  bool _disposed = false;

  @override
  ValueStream<AuthState> get authState => _state$.stream;

  void _emit(AuthState state) {
    if (!_disposed) _state$.add(state);
  }

  static String _createCodeVerifier() => List.generate(
        128,
        (i) => _charset[Random.secure().nextInt(_charset.length)],
      ).join();

  /// Stores a new PKCE verifier and state; returns the authorize URL.
  Future<Uri> authorizationUrl() async {
    _prefs ??= await SharedPreferences.getInstance();
    final codeVerifier = _createCodeVerifier();
    final state = _createCodeVerifier();
    await _prefs!.setString(_prefsKeyCodeVerifier, codeVerifier);
    await _prefs!.setString(_prefsKeyState, state);

    final authUrlWithParams = _config.authorizationEndpoint.replace(
      queryParameters: {
        ..._config.authorizationEndpoint.queryParameters,
        ..._config.extraAuthorizationParameters,
      },
    );
    final grant = oauth2.AuthorizationCodeGrant(
      _config.clientId,
      authUrlWithParams,
      _config.tokenEndpoint,
      codeVerifier: codeVerifier,
      httpClient: _httpClient,
    );
    return grant.getAuthorizationUrl(
      _config.redirectUrl,
      scopes: _config.scopes,
      state: state,
    );
  }

  /// Handles the callback query. On failure: credentials cleared,
  /// SignedOut(noSession), and the error rethrown. Verifier and state are
  /// always removed.
  Future<void> handleRedirect(Map<String, String> parameters) async {
    _prefs ??= await SharedPreferences.getInstance();
    final codeVerifier = _prefs!.getString(_prefsKeyCodeVerifier) ?? '';
    final state = _prefs!.getString(_prefsKeyState) ?? '';

    final grant = oauth2.AuthorizationCodeGrant(
      _config.clientId,
      _config.authorizationEndpoint,
      _config.tokenEndpoint,
      codeVerifier: codeVerifier,
      httpClient: _httpClient,
    );

    // Prime the grant with the expected state and verifier.
    grant.getAuthorizationUrl(
      _config.redirectUrl,
      scopes: _config.scopes,
      state: state,
    );

    try {
      _logger.debug('Handling authorization response...');
      final tempClient = await grant.handleAuthorizationResponse(parameters);
      _logger.debug('Authorization successful.');
      await _validateAndSetCredentials(tempClient.credentials);
    } catch (e, s) {
      _logger.error('Error handling authorization response', e, s);
      await _clearCredentials();
      _emit(const SignedOut(SignedOutReason.noSession));
      rethrow;
    } finally {
      await _prefs!.remove(_prefsKeyCodeVerifier);
      await _prefs!.remove(_prefsKeyState);
    }
  }

  /// The end-session URL. Read it before signOut(): it needs the id token.
  Future<Uri> logoutUrl() async {
    final originalParams = _config.logoutEndpoint.queryParameters;
    final idToken = _credentials?.idToken;
    return _config.logoutEndpoint.replace(
      queryParameters: {
        if (idToken != null) 'id_token_hint': idToken,
        'post_logout_redirect_uri': _config.postLogoutRedirectUrl.toString(),
        'client_id': _config.clientId,
        ...originalParams,
      },
    );
  }

  @override
  Future<void> initialize() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final credentialsJson = _prefs?.getString(_prefsKeyCredentials);
      if (credentialsJson == null) {
        _logger.info('No saved credentials found.');
        _emit(const SignedOut(SignedOutReason.noSession));
        return;
      }

      final credentials = oauth2.Credentials.fromJson(credentialsJson);
      if (credentials.isExpired) {
        _logger.info('Saved credentials expired.');
        if (credentials.refreshToken != null) {
          await _refreshCredentials(credentials);
        } else {
          await _clearCredentials();
          _emit(const SignedOut(SignedOutReason.expired));
        }
      } else {
        _logger.info('Saved credentials appear valid, verifying token...');
        await _validateAndSetCredentials(credentials);
      }
    } catch (e, s) {
      _logger.error('Critical error during session load', e, s);
      await _clearCredentials();
      _emit(const SignedOut(SignedOutReason.expired));
      _credentials = null;
    }
  }

  @override
  Future<void> signOut() async {
    await _clearCredentials();
    _credentials = null;
    _emit(const SignedOut(SignedOutReason.signedOut));
  }

  @override
  Future<String?> accessToken() async {
    if (_state$.value is AuthUnknown) {
      await _state$.firstWhere(
        (s) => s is! AuthUnknown,
        orElse: () => const SignedOut(SignedOutReason.noSession),
      );
    }
    return _credentials?.accessToken;
  }

  @override
  Future<String?> refreshAfterUnauthorized(String rejectedToken) async {
    final current = _credentials;
    if (current == null) return null;
    if (current.accessToken != rejectedToken) {
      return current.accessToken;
    }

    if (_refreshTask != null) {
      _logger.verbose('Already refreshing, joining existing task.');
      try {
        await _refreshTask!;
      } catch (_) {
        // Failure path already emitted SignedOut(expired).
      }
      return _credentials?.accessToken;
    }

    _refreshTask = _executeSyncRefresh(rejectedToken).whenComplete(() {
      _refreshTask = null;
    });

    try {
      await _refreshTask!;
    } catch (_) {
      // Failure path already emitted SignedOut(expired).
    }
    return _credentials?.accessToken;
  }

  /// Refresh with single-flight double-checks against memory and storage.
  Future<void> _executeSyncRefresh(String? originalToken) async {
    final memoryToken = _credentials?.accessToken;
    if (memoryToken != null &&
        memoryToken != originalToken &&
        !(_credentials?.isExpired ?? true)) {
      _logger.info(
        'Token was already updated by a concurrent request. Skipping network refresh.',
      );
      return;
    }

    _prefs ??= await SharedPreferences.getInstance();
    final storedJson = _prefs?.getString(_prefsKeyCredentials);
    if (storedJson != null) {
      final storedCreds = oauth2.Credentials.fromJson(storedJson);
      if (storedCreds.accessToken != memoryToken && !storedCreds.isExpired) {
        _logger.info(
          'Found valid updated credentials in storage. Skipping network refresh.',
        );
        await _validateAndSetCredentials(storedCreds);
        return;
      }
    }

    final current = _credentials;
    if (current == null || current.refreshToken == null) {
      await _clearCredentials();
      _credentials = null;
      _emit(const SignedOut(SignedOutReason.expired));
      return;
    }

    _logger.info('Requesting new tokens from Identity Provider...');
    await _refreshCredentials(current);
  }

  Future<void> _refreshCredentials(
    oauth2.Credentials expiredCredentials,
  ) async {
    _logger.info('Attempting to refresh credentials...');
    try {
      final refreshedCredentials = await expiredCredentials.refresh(
        identifier: _config.clientId,
        httpClient: _httpClient,
      );
      await _validateAndSetCredentials(refreshedCredentials);
    } on oauth2.AuthorizationException catch (e, s) {
      _logger.warning(
        'Stored session is no longer active at the identity provider. '
        'Clearing local credentials.',
        e,
        s,
      );
      await _clearCredentials();
      _credentials = null;
      _emit(const SignedOut(SignedOutReason.expired));
    } catch (e, s) {
      _logger.error('Failed to refresh credentials', e, s);
      await _clearCredentials();
      _credentials = null;
      _emit(const SignedOut(SignedOutReason.expired));
    }
  }

  Future<void> _validateAndSetCredentials(
    oauth2.Credentials credentials,
  ) async {
    try {
      final claims = await _verifier.verify(credentials.accessToken);
      final subject = (claims['email'] ?? claims['sub']) as String?;
      await _saveCredentials(credentials);
      _credentials = credentials;
      _emit(Authenticated(AuthSession(subject: subject)));
      _logger.info('User confirmed: $subject');
    } catch (e, s) {
      _logger.error('Token verification failed', e, s);
      await _clearCredentials();
      _credentials = null;
      _emit(const SignedOut(SignedOutReason.expired));
      rethrow;
    }
  }

  Future<void> _saveCredentials(oauth2.Credentials credentials) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_prefsKeyCredentials, credentials.toJson());
  }

  Future<void> _clearCredentials() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_prefsKeyCredentials);
    await _prefs!.remove(_prefsKeyCodeVerifier);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _state$.close();
  }
}
