import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../service/http_service.dart';

/// One canned answer: the status, the encoded body and the headers.
class _Answer {
  const _Answer(this.status, this.body, this.headers);

  final int status;
  final String body;
  final Map<String, String> headers;
}

/// Canned responses for [HttpService], and a record of the requests made.
class FakeHttpBackend {
  final Map<String, List<_Answer>> _answers = {};
  final List<http.Request> _requests = [];
  late final http.BaseClient _client = MockClient(_answer);

  /// The client to give [HttpService].
  http.BaseClient get client => _client;

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
    final key = _key(method, path);
    _answers.putIfAbsent(key, () => []).add(
          _Answer(
            status,
            body is String ? body : (body == null ? '' : jsonEncode(body)),
            headers,
          ),
        );
  }

  /// Every request received, in order.
  List<http.Request> get requests => List.unmodifiable(_requests);

  static String _key(String method, String path) => '$method $path';

  Future<http.Response> _answer(http.Request request) async {
    _requests.add(request);
    final key = _key(request.method, request.url.path);
    final answers = _answers[key];
    if (answers == null || answers.isEmpty) {
      return _noAnswer(request);
    }
    final answer = answers.length > 1 ? answers.removeAt(0) : answers.first;
    return _response(answer, request);
  }

  http.Response _response(_Answer answer, http.Request request) {
    return http.Response.bytes(
      utf8.encode(answer.body),
      answer.status,
      headers: {
        if (!answer.headers.keys
            .any((name) => name.toLowerCase() == 'content-type'))
          'Content-Type': 'application/json; charset=utf-8',
        ...answer.headers,
      },
      request: request,
    );
  }

  http.Response _noAnswer(http.Request request) {
    final detail =
        'No fake response for ${request.method} ${request.url.path}';
    final body = jsonEncode({
      'title': 'No fake response',
      'status': 404,
      'detail': detail,
    });
    return http.Response.bytes(
      utf8.encode(body),
      404,
      headers: {'Content-Type': 'application/problem+json; charset=utf-8'},
      request: request,
    );
  }
}
