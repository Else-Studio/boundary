import 'package:boundary/testing.dart' as testing;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pumpEventQueue lets chained zero-delay work finish', () async {
    var finished = false;

    Future<void> chain(int rounds) async {
      for (var i = 0; i < rounds; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      finished = true;
    }

    final work = chain(10);

    await testing.pumpEventQueue();

    expect(finished, isTrue);
    await work;
  });
}
