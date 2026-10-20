abstract interface class PostAuthRedirectStore {
  Future<void> save(Uri uri);

  /// The saved URI, once; then null until the next save.
  Future<Uri?> take();
  Future<void> clear();
}

class InMemoryPostAuthRedirectStore implements PostAuthRedirectStore {
  @override
  Future<void> save(Uri uri) => throw UnimplementedError('not implemented');

  @override
  Future<Uri?> take() => throw UnimplementedError('not implemented');

  @override
  Future<void> clear() => throw UnimplementedError('not implemented');
}
