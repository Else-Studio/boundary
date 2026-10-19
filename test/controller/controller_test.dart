import 'dart:async';

import 'package:boundary/boundary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

// A controller whose actions record what happened. `onError` collects errors.
// `ownIt` and `emitTo` are public handles on the protected `own` and `emit`,
// so a test can call them from outside the class.
class RecordingController extends Controller<String> {
  RecordingController({this.slowGate, this.lateGate});

  final List<String> log = [];
  final List<Object> errors = [];
  final Completer<void>? slowGate;
  final Completer<void>? lateGate;
  int disposeCount = 0;

  T ownIt<T extends Object>(T resource) => own(resource);

  void emitTo<T>(StreamController<T> target, T value) => emit(target, value);

  @override
  FutureOr<void> handleAction(String action) {
    switch (action) {
      case 'add':
        log.add('add');
        return null;
      case 'failNow':
        throw ArgumentError('now');
      case 'failLater':
        return _failLater();
      case 'slow':
        return _slow();
      case 'fast':
        log.add('fast');
        return null;
      case 'failOnSignal':
        return _failOnSignal();
    }
    throw StateError('unknown action $action');
  }

  Future<void> _failLater() async {
    await Future<void>.delayed(Duration.zero);
    throw StateError('late');
  }

  Future<void> _slow() async {
    log.add('slow-start');
    await slowGate!.future;
    log.add('slow-end');
  }

  Future<void> _failOnSignal() async {
    await lateGate!.future;
    throw StateError('late');
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    errors.add(error);
  }

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}

// A controller that keeps the default onError.
class PlainController extends Controller<String> {
  @override
  FutureOr<void> handleAction(String action) async {
    await Future<void>.delayed(Duration.zero);
    throw StateError('late');
  }
}

// A subscription that runs [onCancel] when cancelled.
class FakeSubscription implements StreamSubscription<int> {
  FakeSubscription(this.onCancel);

  final void Function() onCancel;

  @override
  Future<void> cancel() {
    onCancel();
    return Future<void>.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LogLevel savedLevel;

  setUp(() => savedLevel = boundaryLogLevel);
  tearDown(() => boundaryLogLevel = savedLevel);

  group('actions', () {
    test('a sync action runs', () async {
      final c = RecordingController();
      addTearDown(c.dispose);

      c.dispatch('add');
      await pumpEventQueue();

      expect(c.log, ['add']);
    });

    test('an error after an await reaches onError', () async {
      final c = RecordingController();
      addTearDown(c.dispose);

      c.dispatch('failLater');
      await pumpEventQueue();

      expect(c.errors, hasLength(1));
      expect(c.errors.single, isA<StateError>());
      expect((c.errors.single as StateError).message, 'late');
    });

    test('a sync throw reaches onError', () async {
      final c = RecordingController();
      addTearDown(c.dispose);

      c.dispatch('failNow');
      await pumpEventQueue();

      expect(c.errors, hasLength(1));
      expect(c.errors.single, isA<ArgumentError>());
      expect((c.errors.single as ArgumentError).message, 'now');
    });

    test('the controller keeps handling actions after an error', () async {
      final c = RecordingController();
      addTearDown(c.dispose);

      c.dispatch('failNow');
      c.dispatch('add');
      await pumpEventQueue();

      expect(c.log, ['add']);
      expect(c.errors, hasLength(1));
    });

    test('a second action starts while a first async one is still running',
        () async {
      final gate = Completer<void>();
      final c = RecordingController(slowGate: gate);
      addTearDown(c.dispose);

      c.dispatch('slow');
      c.dispatch('fast');
      await pumpEventQueue();
      expect(c.log, ['slow-start', 'fast']);

      gate.complete();
      await pumpEventQueue();
      expect(c.log, ['slow-start', 'fast', 'slow-end']);
    });

    test('the default onError swallows the error', () async {
      boundaryLogLevel = LogLevel.critical;
      final c = PlainController();
      addTearDown(c.dispose);

      c.dispatch('failLater');
      await pumpEventQueue();

      // The test fails if the error escapes as an uncaught error.
      expect(c.isDisposed, isFalse);
    });

    test('dispatching after dispose is ignored', () async {
      boundaryLogLevel = LogLevel.critical;
      final c = RecordingController();
      c.dispose();

      c.dispatch('add');
      await pumpEventQueue();

      expect(c.log, isEmpty);
    });

    test('an error that completes after dispose still reaches onError',
        () async {
      final gate = Completer<void>();
      final c = RecordingController(lateGate: gate);

      c.dispatch('failOnSignal');
      await pumpEventQueue();
      c.dispose();
      gate.complete();
      await pumpEventQueue();

      expect(c.errors, hasLength(1));
      expect(c.errors.single, isA<StateError>());
      expect((c.errors.single as StateError).message, 'late');
    });
  });

  group('owned resources', () {
    test('dispose releases every kind of owned resource', () async {
      final c = RecordingController();
      final subject = c.ownIt(BehaviorSubject<int>.seeded(0));
      final broadcast = c.ownIt(StreamController<int>.broadcast());
      final timer = c.ownIt(Timer(const Duration(hours: 1), () {}));
      final source = StreamController<int>();
      addTearDown(() {
        unawaited(source.close());
      });
      c.ownIt(source.stream.listen((_) {}));
      final child = RecordingController();
      c.ownIt(child);
      final text = c.ownIt(TextEditingController());
      expect(source.hasListener, isTrue);

      c.dispose();

      expect(subject.isClosed, isTrue);
      expect(broadcast.isClosed, isTrue);
      expect(timer.isActive, isFalse);
      expect(source.hasListener, isFalse);
      expect(child.isDisposed, isTrue);
      expect(() => text.addListener(() {}), throwsFlutterError);
    });

    test('a composite subscription is disposed with the controller', () async {
      final c = RecordingController();
      final source = StreamController<int>();
      addTearDown(() {
        unawaited(source.close());
      });
      final composite = c.ownIt(CompositeSubscription());
      composite.add(source.stream.listen((_) {}));
      expect(source.hasListener, isTrue);

      c.dispose();

      expect(source.hasListener, isFalse);
      expect(composite.isDisposed, isTrue);
    });

    test('owned resources are released in reverse order of registration',
        () async {
      final c = RecordingController();
      final order = <String>[];
      c.ownIt(FakeSubscription(() => order.add('a')));
      c.ownIt(FakeSubscription(() => order.add('b')));
      c.ownIt(FakeSubscription(() => order.add('c')));

      c.dispose();

      expect(order, ['c', 'b', 'a']);
    });

    test('one failed release does not stop the others', () async {
      final c = RecordingController();
      final first = c.ownIt(StreamController<int>());
      c.ownIt(FakeSubscription(() => throw StateError('cancel')));
      final last = c.ownIt(StreamController<int>());

      c.dispose();
      await pumpEventQueue();

      expect(first.isClosed, isTrue);
      expect(last.isClosed, isTrue);
      expect(c.errors, hasLength(1));
      expect(c.errors.single, isA<StateError>());
      expect((c.errors.single as StateError).message, 'cancel');
    });

    test('own returns the resource it was given', () {
      final c = RecordingController();
      addTearDown(c.dispose);
      final subject = BehaviorSubject<int>.seeded(0);

      expect(identical(c.ownIt(subject), subject), isTrue);
    });

    test('own refuses a resource it does not know how to release', () {
      final c = RecordingController();
      addTearDown(c.dispose);

      expect(() => c.ownIt(Object()), throwsArgumentError);
      expect(() => c.ownIt('text'), throwsArgumentError);
    });

    test('a resource owned after dispose is released at once', () {
      final c = RecordingController();
      c.dispose();
      final stream = StreamController<int>();

      final returned = c.ownIt(stream);

      expect(identical(returned, stream), isTrue);
      expect(stream.isClosed, isTrue);
    });
  });

  group('lifecycle', () {
    test('isDisposed is false until dispose is called', () {
      final c = RecordingController();

      expect(c.isDisposed, isFalse);
      c.dispose();
      expect(c.isDisposed, isTrue);
    });

    test('a second dispose does nothing and does not dispose children again',
        () {
      final c = RecordingController();
      final child = RecordingController();
      c.ownIt(child);

      c.dispose();
      expect(c.dispose, returnsNormally);

      expect(child.disposeCount, 1);
    });
  });

  group('emit', () {
    test('adds the value to the target', () {
      final c = RecordingController();
      addTearDown(c.dispose);
      final s = c.ownIt(BehaviorSubject<int>.seeded(0));

      c.emitTo(s, 1);

      expect(s.value, 1);
    });

    test('does not throw after dispose', () {
      final c = RecordingController();
      final s = c.ownIt(BehaviorSubject<int>.seeded(0));
      c.dispose();

      expect(() => c.emitTo(s, 2), returnsNormally);
    });

    test('does not throw into a closed target', () {
      final c = RecordingController();
      addTearDown(c.dispose);
      final closed = StreamController<int>();
      unawaited(closed.close());

      expect(() => c.emitTo(closed, 3), returnsNormally);
    });
  });
}
