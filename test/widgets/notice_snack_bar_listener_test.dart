import 'package:boundary/boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sut_factory.dart';

void main() {
  late NoticeService notices;

  setUp(() {
    notices = SutFactory.createNoticeService();
  });

  tearDown(() {
    try {
      notices.dispose();
    } catch (_) {}
  });

  testWidgets('the snack bar listener shows a notice', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoticeSnackBarListener(
            notices: notices.notices,
            child: const Text('page'),
          ),
        ),
      ),
    );

    notices.show(const Notice('Saved', level: NoticeLevel.success));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Saved'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Saved'),
        matching: find.byType(SnackBar),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the listener stops listening when it is removed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoticeSnackBarListener(
            notices: notices.notices,
            child: const Text('page'),
          ),
        ),
      ),
    );

    notices.show(const Notice('Saved', level: NoticeLevel.success));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Saved'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(
      () => notices.show(const Notice('late')),
      returnsNormally,
    );
    await tester.pump();
    expect(find.text('late'), findsNothing);
  });

  testWidgets('changing the notices stream resubscribes the listener',
      (tester) async {
    final second = SutFactory.createNoticeService();
    addTearDown(() {
      try {
        second.dispose();
      } catch (_) {}
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoticeSnackBarListener(
            notices: notices.notices,
            child: const Text('page'),
          ),
        ),
      ),
    );

    notices.show(const Notice('Saved', level: NoticeLevel.success));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Saved'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoticeSnackBarListener(
            notices: second.notices,
            child: const Text('page'),
          ),
        ),
      ),
    );
    await tester.pump();

    notices.show(const Notice('old'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('old'), findsNothing);

    // Notices queue. Elapse the first snack bar so the next one is visible.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    second.show(const Notice('new'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('new'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('new'),
        matching: find.byType(SnackBar),
      ),
      findsOneWidget,
    );
  });
}
