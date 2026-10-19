import 'package:boundary/boundary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LogLevel savedLevel;

  setUp(() => savedLevel = boundaryLogLevel);
  tearDown(() => boundaryLogLevel = savedLevel);

  group('useLogger', () {
    test('applies a log level set after the logger was created', () {
      boundaryLogLevel = LogLevel.verbose;
      final log = useLogger('Test', quiet: false);
      boundaryLogLevel = LogLevel.warning;

      log.verbose('v');
      log.debug('d');
      log.info('i');
      log.warning('w');
      log.error('e');

      expect(log.history.map((e) => e.message), ['w', 'e']);
    });

    test('quiet loggers still drop verbose and debug at the lowest level', () {
      boundaryLogLevel = LogLevel.verbose;
      final log = useLogger('Test', quiet: true);

      log.verbose('v');
      log.debug('d');
      log.info('i');

      expect(log.history.map((e) => e.message), ['i']);
    });
  });
}
