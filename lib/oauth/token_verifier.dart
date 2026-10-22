import 'package:http/http.dart' as http;

/// Verifies an access token and returns its claims.
abstract interface class TokenVerifier {
  /// The verified claims of [accessToken]. Throws when it is not valid.
  Future<Map<String, dynamic>> verify(String accessToken);
}

/// Today's JWKS check (RS256 key by `kid` from the JWKS endpoint).
class JwksTokenVerifier implements TokenVerifier {
  JwksTokenVerifier(Uri jwksEndpoint, {http.Client? httpClient});

  @override
  Future<Map<String, dynamic>> verify(String accessToken) {
    throw UnimplementedError('not implemented');
  }
}
