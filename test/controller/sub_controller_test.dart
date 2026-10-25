import 'dart:async';

import 'package:auto_injector/auto_injector.dart';
import 'package:boundary/boundary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

class ParentController extends Controller<String> {
  final List<Object> errors = [];

  C adoptIt<C extends Controller>(C child) => adopt(child);

  ControllerSlot<K, C> slotIt<K, C extends Controller>(
    C Function(K key) create,
  ) =>
      slot(create);

  StreamSubscription<T> listenToIt<T>(
    Stream<T> stream,
    FutureOr<void> Function(T event) onData,
  ) =>
      listenTo(stream, onData);

  @override
  FutureOr<void> handleAction(String action) {}

  @override
  void onError(Object error, StackTrace stackTrace) {
    errors.add(error);
  }
}

class ChildController extends Controller<String> {
  ChildController() {
    _events = own(PublishSubject<String>());
  }

  final List<String> actions = [];
  int disposeCount = 0;
  final Completer<void> gate = Completer<void>();
  void Function()? onDisposed;
  late final PublishSubject<String> _events;

  Stream<String> get events => _events.stream;

  @override
  FutureOr<void> handleAction(String action) async {
    if (action == 'fail') {
      await null;
      throw StateError('child');
    }
    if (action == 'fail later') {
      await gate.future;
      throw StateError('late');
    }
    if (action.startsWith('say ')) {
      _events.add(action.substring(4));
      return;
    }
    actions.add(action);
  }

  @override
  void dispose() {
    disposeCount++;
    onDisposed?.call();
    super.dispose();
  }
}

class SelfHandlingChild extends ChildController {
  final List<Object> ownErrors = [];

  @override
  void onError(Object error, StackTrace stackTrace) {
    ownErrors.add(error);
  }
}

class NoteController extends Controller<void> {
  @override
  FutureOr<void> handleAction(void action) {}
}

class PhotoController extends Controller<void> {
  @override
  FutureOr<void> handleAction(void action) {}
}

class BoardController extends Controller<void> {
  BoardController(this.notes, this.photos);

  final ControllerFactory<NoteController> notes;
  final ControllerFactory<PhotoController> photos;

  @override
  FutureOr<void> handleAction(void action) {}
}

void main() {
  group('adopt', () {
    test('adopt returns the child and does not dispose it', () {
      final parent = ParentController();
      addTearDown(parent.dispose);
      final child = ChildController();

      final returned = parent.adoptIt(child);

      expect(identical(returned, child), isTrue);
      expect(child.isDisposed, isFalse);
      expect(child.disposeCount, 0);
    });

    test('disposing the parent disposes an adopted child', () {
      final parent = ParentController();
      final child = ChildController();
      parent.adoptIt(child);

      parent.dispose();

      expect(child.isDisposed, isTrue);
      expect(child.disposeCount, 1);
    });

    test('adopted children are disposed in reverse order of adoption', () {
      final parent = ParentController();
      final order = <String>[];
      final a = ChildController()..onDisposed = () => order.add('a');
      final b = ChildController()..onDisposed = () => order.add('b');
      parent.adoptIt(a);
      parent.adoptIt(b);

      parent.dispose();

      expect(order, ['b', 'a']);
      expect(a.disposeCount, 1);
      expect(b.disposeCount, 1);
    });

    test('adopting on a disposed parent returns the child already disposed', () {
      final parent = ParentController();
      parent.dispose();
      final child = ChildController();

      final returned = parent.adoptIt(child);

      expect(identical(returned, child), isTrue);
      expect(child.isDisposed, isTrue);
    });

    test('adopting a child that already has a parent throws', () {
      final parent = ParentController();
      addTearDown(parent.dispose);
      final other = ParentController();
      addTearDown(other.dispose);
      final child = ChildController();
      other.adoptIt(child);

      expect(() => parent.adoptIt(child), throwsStateError);
    });

    test('adopting itself throws', () {
      final parent = ParentController();
      addTearDown(parent.dispose);

      expect(() => parent.adoptIt(parent), throwsStateError);
    });
  });

  group('adopted child errors', () {
    test('an adopted child error does not reach the parent', () async {
      final savedLevel = boundaryLogLevel;
      boundaryLogLevel = LogLevel.critical;
      addTearDown(() => boundaryLogLevel = savedLevel);
      final parent = ParentController();
      addTearDown(parent.dispose);
      final child = ChildController();
      parent.adoptIt(child);

      child.dispatch('fail');
      await pumpEventQueue();

      expect(parent.errors, isEmpty);
      expect(child.isDisposed, isFalse);
      expect(child.disposeCount, 0);
    });

    test('a self-handling adopted child keeps its error', () async {
      final parent = ParentController();
      addTearDown(parent.dispose);
      final child = SelfHandlingChild();
      parent.adoptIt(child);

      child.dispatch('fail');
      await pumpEventQueue();

      expect(child.ownErrors.map((e) => e.toString()), [
        StateError('child').toString(),
      ]);
      expect(parent.errors, isEmpty);
    });
  });

  group('slot', () {
    test('activate creates and shows the child for a key', () async {
      final parent = ParentController();
      addTearDown(parent.dispose);
      final slot = parent.slotIt<int, ChildController>(
        (id) => ChildController()..dispatch('load $id'),
      );

      expect(slot.stream.value, isNull);

      final child = slot.activate(7);

      expect(identical(slot.current, child), isTrue);
      expect(identical(slot.stream.value, child), isTrue);
      expect(slot.key, 7);
      await pumpEventQueue();
      expect(child.actions, ['load 7']);
    });

    test('activating the same key keeps the child', () async {
      final parent = ParentController();
      addTearDown(parent.dispose);
      var creates = 0;
      final slot = parent.slotIt<int, ChildController>((id) {
        creates++;
        return ChildController()..dispatch('load $id');
      });
      final seen = <ChildController?>[];
      slot.stream.listen(seen.add);

      final first = slot.activate(7);
      final second = slot.activate(7);
      await pumpEventQueue();

      expect(creates, 1);
      expect(identical(first, second), isTrue);
      expect(seen, [null, first]);
    });

    test('a new key replaces the child, emitting before disposing', () async {
      final parent = ParentController();
      addTearDown(parent.dispose);
      final slot = parent.slotIt<int, ChildController>(
        (id) => ChildController()..dispatch('load $id'),
      );
      final child7 = slot.activate(7);

      var listenerSawDisposed = true;
      var listenerRan = false;
      slot.stream.listen((c) {
        if (identical(c, child7)) return;
        listenerRan = true;
        listenerSawDisposed = child7.isDisposed;
      });

      final child8 = slot.activate(8);

      expect(listenerRan, isTrue);
      expect(listenerSawDisposed, isFalse);
      expect(child7.isDisposed, isTrue);
      expect(identical(slot.current, child8), isTrue);
    });

    test('clear empties the slot and disposes the child', () async {
      final parent = ParentController();
      addTearDown(parent.dispose);
      final slot = parent.slotIt<int, ChildController>(
        (id) => ChildController()..dispatch('load $id'),
      );
      final child7 = slot.activate(7);
      final seen = <ChildController?>[];
      slot.stream.listen(seen.add);
      seen.clear();

      slot.clear();
      await pumpEventQueue();

      expect(slot.stream.value, isNull);
      expect(child7.isDisposed, isTrue);
      expect(slot.key, isNull);
      expect(seen, [null]);

      seen.clear();
      slot.clear();
      await pumpEventQueue();
      expect(seen, isEmpty);
    });

    test('disposing the parent disposes the slot child without emitting null',
        () async {
      final parent = ParentController();
      final slot = parent.slotIt<int, ChildController>(
        (id) => ChildController()..dispatch('load $id'),
      );
      final child7 = slot.activate(7);
      final seen = <Object?>[];
      var done = false;
      slot.stream.listen(seen.add, onDone: () => done = true);

      parent.dispose();
      await pumpEventQueue();

      expect(child7.isDisposed, isTrue);
      expect(seen, [child7]);
      expect(done, isTrue);
      expect(() => slot.activate(8), throwsStateError);
    });

    test('disposing the parent disposes each slot child only once', () {
      final parent = ParentController();
      final slot = parent.slotIt<int, ChildController>(
        (id) => ChildController()..dispatch('load $id'),
      );
      final child7 = slot.activate(7);
      final child8 = slot.activate(8);

      parent.dispose();

      expect(child7.disposeCount, 1);
      expect(child8.disposeCount, 1);
    });
  });

  group('slot child errors', () {
    test('a living slot child error does not reach the parent', () async {
      final savedLevel = boundaryLogLevel;
      boundaryLogLevel = LogLevel.critical;
      addTearDown(() => boundaryLogLevel = savedLevel);
      final parent = ParentController();
      addTearDown(parent.dispose);
      final slot = parent.slotIt<int, ChildController>(
        (id) => ChildController()..dispatch('load $id'),
      );

      slot.activate(7).dispatch('fail');
      await pumpEventQueue();

      expect(parent.errors, isEmpty);
    });

    test('an error from a replaced slot child does not reach the parent',
        () async {
      final parent = ParentController();
      addTearDown(parent.dispose);
      final slot = parent.slotIt<int, ChildController>(
        (id) => ChildController()..dispatch('load $id'),
      );
      final child7 = slot.activate(7);
      child7.dispatch('fail later');
      await pumpEventQueue();

      slot.activate(8);
      child7.gate.complete();
      await pumpEventQueue();

      expect(parent.errors, isEmpty);
    });
  });

  group('listenTo', () {
    test('handles events and catches sync, async and stream errors', () async {
      final parent = ParentController();
      addTearDown(parent.dispose);
      final subject = PublishSubject<int>();
      addTearDown(subject.close);
      final handled = <int>[];

      parent.listenToIt(subject.stream, (event) {
        handled.add(event);
        if (event == 2) throw StateError('sync');
        if (event == 3) {
          return () async {
            await null;
            throw StateError('async');
          }();
        }
      });

      subject.add(1);
      subject.add(2);
      subject.add(3);
      await pumpEventQueue();
      subject.addError(ArgumentError('stream'));
      subject.add(4);
      await pumpEventQueue();

      expect(handled, [1, 2, 3, 4]);
      expect(parent.errors.map((e) => e.toString()), [
        StateError('sync').toString(),
        StateError('async').toString(),
        ArgumentError('stream').toString(),
      ]);
    });

    test('stops listening when the parent is disposed', () {
      final parent = ParentController();
      final subject = PublishSubject<int>();
      addTearDown(subject.close);
      parent.listenToIt(subject.stream, (_) {});

      parent.dispose();

      expect(subject.hasListener, isFalse);
    });
  });

  group('controller factories', () {
    test('factories from the injector create the right child types', () {
      final i = AutoInjector();
      addTearDown(i.dispose);
      addControllerFactory<NoteController>(i, (_) => NoteController());
      addControllerFactory<PhotoController>(i, (_) => PhotoController());
      i.add(BoardController.new);
      i.commit();

      final board = i.get<BoardController>();
      final note = board.notes.create();
      final photo = board.photos.create();
      final note2 = board.notes.create();

      expect(note, isA<NoteController>());
      expect(photo, isA<PhotoController>());
      expect(identical(note, note2), isFalse);
    });
  });

  group('listening across slot children', () {
    test('one subscription follows the current slot child events', () async {
      final parent = ParentController();
      addTearDown(parent.dispose);
      final slot = parent.slotIt<int, ChildController>(
        (id) => ChildController()..dispatch('load $id'),
      );
      final recorded = <String>[];
      parent.listenToIt(
        slot.stream.switchMap(
          (c) => c?.events ?? const Stream<String>.empty(),
        ),
        recorded.add,
      );

      slot.activate(7).dispatch('say a');
      await pumpEventQueue();
      slot.activate(8).dispatch('say b');
      await pumpEventQueue();
      slot.clear();
      await pumpEventQueue();

      expect(recorded, ['a', 'b']);
      expect(parent.errors, isEmpty);
    });
  });
}
