/// Something a controller can own and release by calling [dispose].
abstract interface class Disposable {
  /// Releases what this object holds.
  void dispose();
}
