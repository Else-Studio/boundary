import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:pointycastle/pointycastle.dart' as pc;
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker/talker.dart';

import '../utils.dart';

// --- SHARED DATA MODELS ---

/// Represents the authenticated user data.
class User {
  final oauth2.Credentials credentials;
  const User(this.credentials);
}

/// A sealed class representing the possible authentication errors.
sealed class AuthError implements Exception {
  final String? message;
  const AuthError({this.message});
}

// --- Concrete AuthError Types ---
class NoSessionStored extends AuthError {
  const NoSessionStored();
}

class LoggedOut extends AuthError {
  const LoggedOut();
}

class SessionExpired extends AuthError {
  const SessionExpired({String message = 'User session expired'})
      : super(message: message);
}

class ValidationError extends AuthError {
  const ValidationError({super.message = 'Validation Error'});
}

class PolicyNotAccepted extends AuthError {
  const PolicyNotAccepted();
}

class PolicyExpired extends AuthError {
  const PolicyExpired();
}

class PublicKeyFetchFailed extends AuthError {
  const PublicKeyFetchFailed({String message = 'Failed to fetch public keys.'})
      : super(message: message);
}

class PublicKeyMismatch extends AuthError {
  const PublicKeyMismatch({String message = 'No matching public key found.'})
      : super(message: message);
}

class TokenVerificationFailed extends AuthError {
  const TokenVerificationFailed({
    String message = 'Token signature or format is invalid.',
  }) : super(message: message);
}

/// Holds information for a user who has registered but not yet verified their email.
class RegisteredUserInfo {
  final String keycloakId;
  final String email;

  const RegisteredUserInfo({required this.keycloakId, required this.email});
}

// --- SERVICE CONTRACT (INTERFACE) ---

/// The abstract contract for authentication services within the framework.
abstract class AuthService {
  ValueStream<AsyncResult<User>> get userStream;
  ValueStream<String?> get sessionMessageStream;
  ValueStream<RegisteredUserInfo?> get registeredUserStream; // ADD THIS
  bool get authenticated;
  bool get isLoading;
  oauth2.Client? get client;
  Uri get postLogoutRedirectUrl;

  Future<void> acceptDataPolicy();
  Future<Uri> getAuthorizationUrl({
    String? accessCodeEmail,
    bool embedded = true,
  });
  Future<void> redirected(Map<String, String> parameters);
  Future<Uri> getLogoutUrl();
  Future<void> confirmLocalLogout();
  void clearLoggedOutStateAndPrepareForPolicyCheck();
  void setPendingVerificationInfo(RegisteredUserInfo info); // ADD THIS
  void clearPendingVerificationInfo(); // ADD THIS
  Future<void> refreshCredentialsIfExpired();
  Future<void> forceRefresh();
  void notifySessionMessage(String messageKey);
  void clearSessionMessage();
  Future<void> initialize();
  Future<oauth2.Client> getAuthenticatedClient();
  void dispose();
}

// --- GENERIC BASE IMPLEMENTATION ---

const String _prefsKeyCredentials = 'oauth_credentials';
const String _prefsKeyCodeVerifier = 'codeVerifier';
const String _prefsKeyState = 'authState';

/// A base implementation of [AuthService] that handles the complete OAuth2 PKCE
/// flow, JWT validation, and secure credential storage.
abstract class BaseAuthService implements AuthService {
  @protected
  final Talker logger;

  @protected
  late final String clientId;
  @protected
  late final String clientScopes;
  @protected
  late final Uri authorizationEndpoint;
  @protected
  late final Uri tokenEndpoint;
  @protected
  late final Uri publicKeyEndpoint;
  @protected
  late final Uri logoutEndpoint;
  @protected
  late final Uri redirectUrl;
  @override
  late final Uri postLogoutRedirectUrl;

  oauth2.Client? _client;
  @override
  oauth2.Client? get client => _client;

  String? _userEmail;
  SharedPreferences? _prefs;

  final _user$ = BehaviorSubject<AsyncResult<User>>.seeded(const Loading());
  final _sessionMessage$ = BehaviorSubject<String?>.seeded(null);
  final _registeredUser$ =
      BehaviorSubject<RegisteredUserInfo?>.seeded(null); // ADD THIS

  @override
  ValueStream<AsyncResult<User>> get userStream => _user$.stream;
  @override
  ValueStream<String?> get sessionMessageStream => _sessionMessage$.stream;
  @override
  ValueStream<RegisteredUserInfo?> get registeredUserStream =>
      _registeredUser$.stream; // ADD THIS
  @override
  bool get authenticated => _user$.value is Data<User>;
  @override
  bool get isLoading => _user$.value is Loading;

  BaseAuthService({required String loggerLabel})
      : logger = useLogger(loggerLabel) {
    _loadEnvironmentVariables();
  }

  void _loadEnvironmentVariables() {
    clientId = dotenv.get('CLIENT_ID');
    clientScopes = dotenv.get('CLIENT_SCOPES');
    authorizationEndpoint = Uri.parse(dotenv.get('AUTHORIZATION_ENDPOINT'));
    tokenEndpoint = Uri.parse(dotenv.get('TOKEN_ENDPOINT'));
    publicKeyEndpoint = Uri.parse(dotenv.get('PUBLICKEY_ENDPOINT'));
    logoutEndpoint = Uri.parse(dotenv.get('LOGOUT_ENDPOINT'));
    redirectUrl = Uri.parse(dotenv.get('REDIRECT_URL'));
    postLogoutRedirectUrl = Uri.parse(dotenv.get('LOGOUT_REDIRECT_URL'));
  }

  /// Hook for subclasses to perform app-specific pre-authentication checks.
  @protected
  Future<AuthError?> performPreAuthenticationChecks(SharedPreferences prefs);

  /// Reloads and re-validates the current session state.
  @protected
  void reInitializeAndLoadSession() {
    _initializeAndLoadSession();
  }

  @override
  Future<void> initialize() async {
    await _initializeAndLoadSession();
  }

  @override
  Future<oauth2.Client> getAuthenticatedClient() async {
    // 1. If we are currently loading (e.g. startup or refresh), wait for it to settle.
    if (isLoading) {
      logger.debug(
        'getAuthenticatedClient: Service is loading. Waiting for readiness...',
      );
      try {
        await _user$.firstWhere((result) => result is! Loading).timeout(
          const Duration(seconds: 15),
        );
      } on TimeoutException {
        throw const SessionExpired(
          message: 'Authentication timed out during initialization.',
        );
      }
    }

    // 2. Check if we have a client.
    final currentClient = _client;
    if (currentClient == null || !authenticated) {
      throw const NoSessionStored();
    }

    // 3. Handle proactive refresh if the token is expired.
    if (currentClient.credentials.isExpired) {
      logger.info('getAuthenticatedClient: Credentials expired. Refreshing...');
      await refreshCredentialsIfExpired();

      final refreshedClient = _client;
      if (refreshedClient == null || !authenticated) {
        throw const SessionExpired(
          message: 'Session expired and refresh failed.',
        );
      }
      return refreshedClient;
    }

    return currentClient;
  }

  Future<void> _initializeAndLoadSession() async {
    if (_user$.value is! Loading<User>) {
      _user$.add(const Loading());
    }

    try {
      _prefs ??= await SharedPreferences.getInstance();
      final preAuthError = await performPreAuthenticationChecks(_prefs!);
      if (preAuthError != null) {
        logger.info(
          "Pre-authentication check failed: ${preAuthError.runtimeType}",
        );
        _user$.add(Failure(preAuthError));
        return;
      }
      logger.verbose("Pre-authentication checks passed.");

      final credentialsJson = _prefs?.getString(_prefsKeyCredentials);
      if (credentialsJson == null) {
        logger.info('No saved credentials found.');
        _user$.add(const Failure(NoSessionStored()));
        return;
      }

      final credentials = oauth2.Credentials.fromJson(credentialsJson);
      if (credentials.isExpired) {
        logger.info('Saved credentials expired.');
        if (credentials.refreshToken != null) {
          await _refreshCredentials(credentials);
        } else {
          await _clearCredentials();
          _user$.add(const Failure(SessionExpired()));
        }
      } else {
        logger.info('Saved credentials appear valid, verifying token...');
        await _validateAndSetClient(credentials);
      }
    } catch (e, s) {
      logger.error('Critical error during session load', e, s);
      await _clearCredentials();
      _user$.add(
        Failure(
          e is AuthError ? e : TokenVerificationFailed(message: e.toString()),
        ),
      );
      _client = null;
    }
  }

  static const String _charset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  static String _createCodeVerifier() => List.generate(
        128,
        (i) => _charset[Random.secure().nextInt(_charset.length)],
      ).join();

  @override
  Future<Uri> getAuthorizationUrl({
    String? accessCodeEmail,
    bool embedded = true,
  }) async {
    _prefs ??= await SharedPreferences.getInstance();
    final codeVerifier = _createCodeVerifier();
    final state = _createCodeVerifier(); // Generate random state
    await _prefs!.setString(_prefsKeyCodeVerifier, codeVerifier);
    await _prefs!.setString(_prefsKeyState, state);

    final authUrlWithParams = authorizationEndpoint.replace(
      queryParameters: {
        ...authorizationEndpoint.queryParameters,
        if (accessCodeEmail != null) 'email': accessCodeEmail,
        'embedded': embedded ? 'true' : 'false',
      },
    );
    final grant = oauth2.AuthorizationCodeGrant(
      clientId,
      authUrlWithParams,
      tokenEndpoint,
      codeVerifier: codeVerifier,
    );
    return grant.getAuthorizationUrl(
      redirectUrl,
      scopes: clientScopes.split(','),
      state: state,
    );
  }

  @override
  Future<void> redirected(Map<String, String> parameters) async {
    _prefs ??= await SharedPreferences.getInstance();
    _user$.add(const Loading());
    final codeVerifier = _prefs!.getString(_prefsKeyCodeVerifier) ?? '';
    final state = _prefs!.getString(_prefsKeyState) ?? '';

    // We MUST instantiate the grant and prime it with the same state and verifier
    // that were used when the authorization URL was generated.
    final grant = oauth2.AuthorizationCodeGrant(
      clientId,
      authorizationEndpoint,
      tokenEndpoint,
      codeVerifier: codeVerifier,
    );

    // Priming the grant with the expected state.
    grant.getAuthorizationUrl(
      redirectUrl,
      scopes: clientScopes.split(','),
      state: state,
    );

    try {
      logger.debug('Handling authorization response...');
      final tempClient = await grant.handleAuthorizationResponse(parameters);
      logger.debug('Authorization successful.');

      await _validateAndSetClient(tempClient.credentials);
    } catch (e, s) {
      logger.error('Error handling authorization response', e, s);
      await _clearCredentials();
      _user$.add(
        Failure(e is AuthError ? e : SessionExpired(message: e.toString())),
      );
      _client = null;
      rethrow; // Rethrow so CallbackController can handle it
    } finally {
      // Always clear the verifier and state after use
      await _prefs!.remove(_prefsKeyCodeVerifier);
      await _prefs!.remove(_prefsKeyState);
    }
  }

  @override
  Future<Uri> getLogoutUrl() async {
    final originalParams = logoutEndpoint.queryParameters;
    final idToken = _client?.credentials.idToken;
    return logoutEndpoint.replace(
      queryParameters: {
        if (idToken != null) 'id_token_hint': idToken,
        'post_logout_redirect_uri': postLogoutRedirectUrl.toString(),
        'client_id': clientId,
        ...originalParams,
      },
    );
  }

  @override
  Future<void> confirmLocalLogout() async {
    await _clearCredentials();
    _client = null;
    _user$.add(const Failure(LoggedOut()));
  }

  @override
  void clearLoggedOutStateAndPrepareForPolicyCheck() {
    if (_user$.value is Failure<User> &&
        (_user$.value as Failure<User>).error is LoggedOut) {
      _user$.add(const Failure(NoSessionStored()));
    }
  }

  @override
  Future<void> refreshCredentialsIfExpired() async {
    final current = _client?.credentials;
    if (current == null || !current.isExpired) return;

    await forceRefresh();
  }

  Future<void>? _refreshTask;

  @override
  Future<void> forceRefresh() {
    final originalToken = _client?.credentials.accessToken;

    if (_refreshTask != null) {
      logger.verbose('forceRefresh: Already refreshing, joining existing task.');
      return _refreshTask!;
    }

    _refreshTask = _executeSyncRefresh(originalToken).whenComplete(() {
      _refreshTask = null;
    });
    return _refreshTask!;
  }

  /// Executes a refresh with synchronization and storage-level double-checking.
  Future<void> _executeSyncRefresh(String? originalToken) async {
    // 1. Double-check memory: Maybe another concurrent request just finished?
    final memoryToken = _client?.credentials.accessToken;
    if (memoryToken != null && memoryToken != originalToken && !(_client?.credentials.isExpired ?? true)) {
      logger.info('SyncRefresh: Token was already updated by a concurrent request. Skipping network refresh.');
      return;
    }

    // 2. Double-check storage: Maybe another tab refreshed it?
    _prefs ??= await SharedPreferences.getInstance();
    final storedJson = _prefs?.getString(_prefsKeyCredentials);
    if (storedJson != null) {
      final storedCreds = oauth2.Credentials.fromJson(storedJson);
      if (storedCreds.accessToken != memoryToken && !storedCreds.isExpired) {
        logger.info('SyncRefresh: Found valid updated credentials in storage. Skipping network refresh.');
        await _validateAndSetClient(storedCreds);
        return;
      }
    }

    // 3. Perform the actual network refresh if neither check helped.
    final currentClient = _client;
    if (currentClient == null || currentClient.credentials.refreshToken == null) {
      throw const SessionExpired(message: 'No refresh token available.');
    }

    logger.info('SyncRefresh: Requesting new tokens from Identity Provider...');
    await _refreshCredentials(currentClient.credentials);
  }

  Future<void> _refreshCredentials(
    oauth2.Credentials expiredCredentials,
  ) async {
    logger.info('Attempting to refresh credentials...');
    // Only show loading if we aren't already authenticated (e.g. initial load)
    if (_user$.value is! Data<User>) {
      _user$.add(const Loading());
    }
    try {
      final refreshedCredentials = await expiredCredentials.refresh(
        identifier: clientId,
      );
      await _validateAndSetClient(refreshedCredentials, isRefresh: true);
    } on oauth2.AuthorizationException {
      logger.warning(
        'Stored session is no longer active at the identity provider. Clearing local credentials.',
      );
      await _clearCredentials();
      _user$.add(
        Failure(
          SessionExpired(message: 'Stored session expired. Please sign in again.'),
        ),
      );
      _client = null;
    } catch (e, s) {
      logger.error('Failed to refresh credentials', e, s);
      await _clearCredentials();
      _user$.add(
        Failure(
          e is AuthError ? e : SessionExpired(message: 'Failed to refresh: $e'),
        ),
      );
      _client = null;
    }
  }

  Future<void> _validateAndSetClient(
    oauth2.Credentials credentials, {
    bool isRefresh = false,
  }) async {
    _client = oauth2.Client(credentials, identifier: clientId, secret: null);
    try {
      logger.debug('Auth Client: $_client');

      final verifiedPayload = await verifyAndGetPayload();
      _userEmail = verifiedPayload['email'] as String?;
      await _saveCredentials(credentials);
      _user$.add(Data(User(credentials)));

      logger.info('User confirmed: $_userEmail');
    } catch (e, s) {
      final authError = e is AuthError ? e : TokenVerificationFailed(message: e.toString());
      logger.error('Token verification failed. Reason: ${authError.message}', e, s);
      await _clearCredentials();
      _user$.add(Failure(authError));
      _client = null;
      if (e is AuthError) rethrow; // Keep original behavior for AuthErrors if needed
    }
  }

  Future<void> _saveCredentials(oauth2.Credentials credentials) async =>
      await _prefs?.setString(_prefsKeyCredentials, credentials.toJson());
  Future<void> _clearCredentials() async {
    _userEmail = null;
    await _prefs?.remove(_prefsKeyCredentials);
    await _prefs?.remove(_prefsKeyCodeVerifier);
  }

  @override
  void setPendingVerificationInfo(RegisteredUserInfo info) {
    _registeredUser$.add(info);
  }

  @override
  void clearPendingVerificationInfo() {
    _registeredUser$.add(null);
  }

  @protected
  Future<Map<String, dynamic>> verifyAndGetPayload() async {
    final accessToken = _client!.credentials.accessToken;
    try {
      final kid = _findKidFromJwt(accessToken);
      final jwksResponse = await http.get(publicKeyEndpoint);
      if (jwksResponse.statusCode != 200) throw const PublicKeyFetchFailed();
      final keys = json.decode(jwksResponse.body);
      final keyData = keys['keys']?.firstWhere(
        (k) => k['kid'] == kid,
        orElse: () => null,
      );
      if (keyData == null) throw const PublicKeyMismatch();
      final nBytes = base64Url.decode(base64Url.normalize(keyData['n']));
      final eBytes = base64Url.decode(base64Url.normalize(keyData['e']));
      final publicKey = RSAPublicKey.raw(
        pc.RSAPublicKey(
          _convertBytesToBigInt(nBytes),
          _convertBytesToBigInt(eBytes),
        ),
      );
      final jwt = JWT.verify(accessToken, publicKey, checkNotBefore: false);
      return jwt.payload as Map<String, dynamic>;
    } on JWTExpiredException {
      throw const SessionExpired(message: 'Token has expired.');
    } on JWTException catch (ex) {
      throw TokenVerificationFailed(
        message: 'JWT validation failed: ${ex.message}',
      );
    } catch (e) {
      throw TokenVerificationFailed(
        message: 'Unexpected error during token verification: $e',
      );
    }
  }

  String? _findKidFromJwt(String token) {
    try {
      final parts = token.split('.');
      final header = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
      );
      return header['kid'];
    } catch (e) {
      return null;
    }
  }

  BigInt _convertBytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  @override
  void notifySessionMessage(String messageKey) =>
      _sessionMessage$.add(messageKey);
  @override
  void clearSessionMessage() => _sessionMessage$.add(null);
  @override
  void dispose() {
    _user$.close();
    _sessionMessage$.close();
  }
}
