import 'package:boundary/boundary.dart';
import 'package:boundary/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/sut_factory.dart';

/// An async counter: 'add' waits three zero-delay rounds, then adds one.
class CounterController extends Controller<String> {
  final BehaviorSubject<int> count = BehaviorSubject<int>.seeded(0);

  @override
  Future<void> handleAction(String action) async {
    if (action != 'add') return;
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    count.add(count.value + 1);
  }

  @override
  void dispose() {
    count.close();
    super.dispose();
  }
}

void main() {
  test('act runs an action to the end', () async {
    final controller = CounterController();
    final ControllerHarness<String, CounterController> harness =
        SutFactory.createControllerHarness(controller);

    final counts = harness.record(controller.count);

    await harness.act('add');
    await harness.act('add');

    expect(counts, [0, 1, 2]);
    harness.dispose();
  });

  test('dispose stops the recordings and disposes the controller', () async {
    final controller = CounterController();
    final harness = SutFactory.createControllerHarness(controller);
    final other = BehaviorSubject<int>.seeded(1);
    addTearDown(other.close);

    final values = harness.record(other);

    other.add(2);
    await Future<void>.delayed(Duration.zero);
    expect(values, [1, 2]);

    harness.dispose();

    other.add(3);
    await Future<void>.delayed(Duration.zero);

    expect(controller.isDisposed, isTrue);
    expect(values, [1, 2]);
  });
}
