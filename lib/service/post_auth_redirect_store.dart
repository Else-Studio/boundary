/// Keeps the route an unauthenticated user asked for, until sign-in is done.
abstract interface class PostAuthRedirectStore {
  /// Keeps [uri], replacing any saved one.
  Future<void> save(Uri uri);

  /// The saved URI, once; then null until the next save.
  Future<Uri?> take();
  /// Forgets the saved URI.
  Future<void> clear();
}

/// Keeps the redirect in memory. Enough for apps that never leave the page
/// to sign in.
class InMemoryPostAuthRedirectStore implements PostAuthRedirectStore {
  Uri? _uri;

  @override
  Future<void> save(Uri uri) async {
    _uri = uri;
  }

  @override
  Future<Uri?> take() async {
    final uri = _uri;
    _uri = null;
    return uri;
  }

  @override
  Future<void> clear() async {
    _uri = null;
  }
}
