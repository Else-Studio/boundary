/// Configuration for [OAuthAuthService], replacing the old dotenv keys.
class OAuthConfig {
  const OAuthConfig({
    required this.clientId,
    required this.scopes,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.jwksEndpoint,
    required this.logoutEndpoint,
    required this.redirectUrl,
    required this.postLogoutRedirectUrl,
    this.extraAuthorizationParameters = const {},
  });

  final String clientId;
  final List<String> scopes;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri jwksEndpoint;
  final Uri logoutEndpoint;
  final Uri redirectUrl;
  final Uri postLogoutRedirectUrl;

  /// Extra query parameters added to the authorize URL (replaces `embedded`/`email`).
  final Map<String, String> extraAuthorizationParameters;
}
