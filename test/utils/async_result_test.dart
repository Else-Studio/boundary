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
    test('prints its error and nothing else', () {
      final result = Failure<int>(StateError('no session'));

      expect(result, isA<AsyncResult<int>>());
      expect(result.toString(), 'Failure(Bad state: no session)');
      expect(result.dataOrNull, isNull);
      expect(result.error, isA<StateError>());
      expect(result.stackTrace, isNull);
    });
  });
}
