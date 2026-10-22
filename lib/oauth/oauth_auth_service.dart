import 'package:http/http.dart' as http;
import 'package:rxdart/rxdart.dart';

import '../service/auth_service.dart';
import 'oauth_config.dart';
import 'token_verifier.dart';

/// Web-only OAuth2 PKCE adapter kept for reference.
@Deprecated(
    'Web-only OAuth kept for reference. New apps use StoredTokenAuthService.')
class OAuthAuthService implements AuthService {
  OAuthAuthService(
    OAuthConfig config, {
    http.Client? httpClient,
    TokenVerifier? verifier,
  });

  /// Stores a new PKCE verifier and state; returns the authorize URL.
  Future<Uri> authorizationUrl() =>
      throw UnimplementedError('not implemented');

  /// Handles the callback query. On failure: credentials cleared,
  /// SignedOut(noSession), and the error rethrown. Verifier and state are
  /// always removed.
  Future<void> handleRedirect(Map<String, String> parameters) =>
      throw UnimplementedError('not implemented');

  /// The end-session URL. Read it before signOut(): it needs the id token.
  Future<Uri> logoutUrl() => throw UnimplementedError('not implemented');

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
