import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../service/post_auth_redirect_store.dart';

const String _prefsKey = 'post_auth_redirect_intent';

/// SharedPreferences-backed [PostAuthRedirectStore] for OAuth redirects that
/// leave the page.
class SharedPreferencesPostAuthRedirectStore implements PostAuthRedirectStore {
  SharedPreferencesPostAuthRedirectStore({
    DateTime Function()? now,
    this.lifetime = const Duration(minutes: 5),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration lifetime;

  @override
  Future<void> save(Uri uri) async {
    final prefs = await SharedPreferences.getInstance();
    final intent = {
      'uri': uri.toString(),
      'timestamp': _now().millisecondsSinceEpoch,
    };
    await prefs.setString(_prefsKey, jsonEncode(intent));
  }

  @override
  Future<Uri?> take() async {
    final prefs = await SharedPreferences.getInstance();
    final intentJson = prefs.getString(_prefsKey);
    if (intentJson == null) return null;

    await prefs.remove(_prefsKey);

    try {
      final intent = jsonDecode(intentJson);
      if (intent is! Map) return null;
      final uriString = intent['uri'];
      final timestampMillis = intent['timestamp'];
      if (uriString is! String || timestampMillis is! int) return null;

      final storedTime = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
      final expiryTime = storedTime.add(lifetime);
      if (_now().isAfter(expiryTime)) return null;

      return Uri.parse(uriString);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
