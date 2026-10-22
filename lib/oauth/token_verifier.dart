import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/pointycastle.dart' as pc;

/// Verifies an access token and returns its claims.
abstract interface class TokenVerifier {
  /// The verified claims of [accessToken]. Throws when it is not valid.
  Future<Map<String, dynamic>> verify(String accessToken);
}

/// Today's JWKS check (RS256 key by `kid` from the JWKS endpoint).
class JwksTokenVerifier implements TokenVerifier {
  JwksTokenVerifier(this._jwksEndpoint, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final Uri _jwksEndpoint;
  final http.Client _httpClient;

  @override
  Future<Map<String, dynamic>> verify(String accessToken) async {
    try {
      final kid = _findKidFromJwt(accessToken);
      final jwksResponse = await _httpClient.get(_jwksEndpoint);
      if (jwksResponse.statusCode != 200) {
        throw StateError('Failed to fetch public keys.');
      }
      final keys = json.decode(jwksResponse.body);
      final keyData = keys['keys']?.firstWhere(
        (k) => k['kid'] == kid,
        orElse: () => null,
      );
      if (keyData == null) {
        throw StateError('No matching public key found.');
      }
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
      throw StateError('Token has expired.');
    } on JWTException catch (ex) {
      throw StateError('JWT validation failed: ${ex.message}');
    }
  }

  String? _findKidFromJwt(String token) {
    try {
      final parts = token.split('.');
      final header = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
      );
      return header['kid'];
    } catch (_) {
      return null;
    }
  }

  BigInt _convertBytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}
