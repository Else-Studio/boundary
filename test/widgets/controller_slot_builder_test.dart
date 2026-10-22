import 'dart:async';

import 'package:boundary/boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class ParentController extends Controller<String> {
  ControllerSlot<K, C> slotIt<K, C extends Controller>(
    C Function(K key) create,
  ) =>
      slot(create);

  @override
  FutureOr<void> handleAction(String action) {}
}

class ChildController extends Controller<String> {
  @override
  FutureOr<void> handleAction(String action) {}
}

class CounterView extends StatefulWidget {
  const CounterView({super.key});

  @override
  State<CounterView> createState() => _CounterViewState();
}

class _CounterViewState extends State<CounterView> {
  int n = 0;

  @override
  Widget build(BuildContext context) {
    final child = context.read<ChildController>();
    return GestureDetector(
      onTap: () => setState(() => n++),
      child: Text('child ${child.hashCode} count $n'),
    );
  }
}

void main() {
  testWidgets('shows empty, then the slot child, resets state on replace',
      (tester) async {
    final parent = ParentController();
    addTearDown(parent.dispose);
    final slot = parent.slotIt<int, ChildController>((_) => ChildController());

    await tester.pumpWidget(
      MaterialApp(
        home: ControllerSlotBuilder<ChildController>(
          stream: slot.stream,
          builder: (_, c) => const CounterView(),
          empty: (_) => const Text('none'),
        ),
      ),
    );

    expect(find.text('none'), findsOneWidget);

    final child7 = slot.activate(7);
    await tester.pump();
    expect(find.text('child ${child7.hashCode} count 0'), findsOneWidget);

    await tester.tap(find.text('child ${child7.hashCode} count 0'));
    await tester.pump();
    expect(find.text('child ${child7.hashCode} count 1'), findsOneWidget);

    final child8 = slot.activate(8);
    await tester.pump();
    expect(find.text('child ${child8.hashCode} count 0'), findsOneWidget);

    slot.clear();
    await tester.pump();
    expect(find.text('none'), findsOneWidget);
  });

  testWidgets('the first frame uses the slot current child', (tester) async {
    final parent = ParentController();
    addTearDown(parent.dispose);
    final slot = parent.slotIt<int, ChildController>((_) => ChildController());
    final child7 = slot.activate(7);

    await tester.pumpWidget(
      MaterialApp(
        home: ControllerSlotBuilder<ChildController>(
          stream: slot.stream,
          builder: (_, c) => const CounterView(),
          empty: (_) => const Text('none'),
        ),
      ),
    );

    expect(find.text('child ${child7.hashCode} count 0'), findsOneWidget);
  });
}
