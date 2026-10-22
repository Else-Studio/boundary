import '../service/post_auth_redirect_store.dart';

/// SharedPreferences-backed [PostAuthRedirectStore] for OAuth redirects that
/// leave the page.
class SharedPreferencesPostAuthRedirectStore implements PostAuthRedirectStore {
  SharedPreferencesPostAuthRedirectStore({
    DateTime Function()? now,
    Duration lifetime = const Duration(minutes: 5),
  });

  @override
  Future<void> save(Uri uri) => throw UnimplementedError('not implemented');

  @override
  Future<Uri?> take() => throw UnimplementedError('not implemented');

  @override
  Future<void> clear() => throw UnimplementedError('not implemented');
}
