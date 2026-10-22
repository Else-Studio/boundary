import 'dart:async';

import 'package:boundary/boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('AsyncResultBuilder with defaults', () {
    testWidgets('loading shows a progress indicator', (tester) async {
      await tester.pumpWidget(
        wrap(
          AsyncResultBuilder<int>(
            stream: Stream.value(const Loading()),
            data: (_, n) => Text('n=$n'),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('data shows the data builder', (tester) async {
      await tester.pumpWidget(
        wrap(
          AsyncResultBuilder<int>(
            stream: Stream.value(const Data(3)),
            data: (_, n) => Text('n=$n'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('n=3'), findsOneWidget);
    });

    testWidgets('failure shows the default error text', (tester) async {
      await tester.pumpWidget(
        wrap(
          AsyncResultBuilder<int>(
            stream: Stream.value(Failure(StateError('x'))),
            data: (_, n) => Text('n=$n'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Something went wrong.'), findsOneWidget);
    });

    testWidgets('empty shows nothing', (tester) async {
      final subject = BehaviorSubject<AsyncResult<int>>.seeded(const Data(3));
      addTearDown(subject.close);

      await tester.pumpWidget(
        wrap(
          AsyncResultBuilder<int>(
            stream: subject,
            data: (_, n) => Text('n=$n'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('n=3'), findsOneWidget);

      subject.add(const Empty());
      await tester.pump();
      await tester.pump();

      expect(find.byType(Text), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('AsyncResultBuilder with builders', () {
    testWidgets('loading uses the loading builder', (tester) async {
      await tester.pumpWidget(
        wrap(
          AsyncResultBuilder<int>(
            stream: Stream.value(const Loading()),
            data: (_, n) => Text('n=$n'),
            loading: (_) => const Text('wait'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('wait'), findsOneWidget);
    });

    testWidgets('data still shows the data builder', (tester) async {
      await tester.pumpWidget(
        wrap(
          AsyncResultBuilder<int>(
            stream: Stream.value(const Data(3)),
            data: (_, n) => Text('n=$n'),
            loading: (_) => const Text('wait'),
            empty: (_) => const Text('none'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('n=3'), findsOneWidget);
    });

    testWidgets('failure uses the failure builder', (tester) async {
      await tester.pumpWidget(
        wrap(
          AsyncResultBuilder<int>(
            stream: Stream.value(Failure(StateError('x'))),
            data: (_, n) => Text('n=$n'),
            failure: (_, f) => Text('err ${f.error}'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('err Bad state: x'), findsOneWidget);
    });

    testWidgets('empty uses the empty builder', (tester) async {
      await tester.pumpWidget(
        wrap(
          AsyncResultBuilder<int>(
            stream: Stream.value(const Empty()),
            data: (_, n) => Text('n=$n'),
            empty: (_) => const Text('none'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('none'), findsOneWidget);
    });
  });

  testWidgets('a stream with no event yet shows loading', (tester) async {
    final controller = StreamController<AsyncResult<int>>();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      // close() never completes if nobody subscribed.
      if (controller.hasListener) await controller.close();
    });

    await tester.pumpWidget(
      wrap(
        AsyncResultBuilder<int>(
          stream: controller.stream,
          data: (_, n) => Text('n=$n'),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('n=1'), findsNothing);
  });

  testWidgets('a value stream with no value yet shows loading', (tester) async {
    final subject = BehaviorSubject<AsyncResult<int>>();
    addTearDown(subject.close);

    await tester.pumpWidget(
      wrap(
        AsyncResultBuilder<int>(
          stream: subject,
          data: (_, n) => Text('n=$n'),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('n=1'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a seeded value shows on the first frame', (tester) async {
    final subject = BehaviorSubject<AsyncResult<int>>.seeded(const Data(5));
    addTearDown(subject.close);

    await tester.pumpWidget(
      wrap(
        AsyncResultBuilder<int>(
          stream: subject,
          data: (_, n) => Text('n=$n'),
        ),
      ),
    );

    expect(find.text('n=5'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a stream error shows the failure builder', (tester) async {
    final controller = StreamController<AsyncResult<int>>();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      // close() never completes if nobody subscribed.
      if (controller.hasListener) await controller.close();
    });
    Object? seenError;

    // Push the error when the builder subscribes, so a stub that never
    // listens fails the assertion without leaving an unhandled stream error.
    controller.onListen = () {
      controller.addError(StateError('gone'));
    };

    await tester.pumpWidget(
      wrap(
        AsyncResultBuilder<int>(
          stream: controller.stream,
          data: (_, n) => Text('n=$n'),
          failure: (_, f) {
            seenError = f.error;
            return Text('err ${f.error}');
          },
        ),
      ),
    );
    await tester.pump();

    expect(seenError, isA<StateError>());
    expect((seenError as StateError).message, 'gone');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
