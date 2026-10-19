import 'package:boundary/boundary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dart:core Error', () {
    test('is visible to users who import boundary without hide', () {
      final Object stateError = StateError('boom');
      final Object argumentError = ArgumentError('x');

      expect(stateError is Error, isTrue);
      expect(argumentError is Error, isTrue);
    });
  });

  group('Failure', () {
    test('carries its error and message key', () {
      const result =
          Failure<int>(NoSessionStored(), messageKey: 'error.session');

      expect(result, isA<AsyncResult<int>>());
      expect(result.dataOrNull, isNull);
      expect(result.error, isA<NoSessionStored>());
      expect(result.messageKey, 'error.session');
      expect(result.stackTrace, isNull);
    });
  });
}
