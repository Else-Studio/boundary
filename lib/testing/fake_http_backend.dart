import 'package:http/http.dart' as http;

/// Canned responses for [HttpService], and a record of the requests made.
class FakeHttpBackend {
  /// The client to give [HttpService].
  http.BaseClient get client => throw UnimplementedError('not implemented');

  /// Answers [method] [path] (the URL path only). Several answers for one key
  /// are served in order, and the last one repeats. [body] is a String or is
  /// jsonEncode'd.
  void on(
    String method,
    String path, {
    int status = 200,
    Object? body,
    Map<String, String> headers = const {},
  }) {
    throw UnimplementedError('not implemented');
  }

  /// Every request received, in order.
  List<http.Request> get requests => throw UnimplementedError('not implemented');
}
