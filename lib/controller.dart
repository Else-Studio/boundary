import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:rxdart/rxdart.dart';

import 'disposable.dart';
import 'router.dart';
import 'utils.dart';

part 'controller_slot.dart';

/// A route controller that stays alive when its route type returns with
/// different params. (Was RouteAware.)
abstract interface class RouteUpdatable<R extends ConfigurationBase> {
  /// Called instead of recreating the controller. Not called for an equal
  /// route, and never together with enter for the same change.
  void update(R route);
}

/// An abstract base class for controllers managing state via actions.
///
/// It handles dispatching actions of type [A] from the View and processing them.
/// It also manages the lifecycle of internal and external stream subscriptions.
abstract class Controller<A> {
  // Internal StreamController to handle actions dispatched from the View.
  // Using a standard StreamController as replay of actions isn't needed.
  late final StreamController<A> _actionController;

  // Subscription to the internal action stream.
  StreamSubscription<A>? _actionSubscription;

  // Release closures for owned resources, in registration order.
  final List<FutureOr<void> Function()> _releasers = [];

  /// Parent set by [adopt] or by a [ControllerSlot]; separate from ownership.
  Controller? _parent;

  bool _isDisposed = false;

  Controller() {
    _actionController = StreamController<A>();
    _actionSubscription = _actionController.stream.listen(_run);
  }

  /// Queues [action] for [handleAction]. After dispose: logs a warning, no-op.
  void dispatch(A action) {
    if (_isDisposed || _actionController.isClosed) {
      appLogger.warning(
        'Attempted to dispatch action ($action) on a disposed controller ($runtimeType).',
      );
      return;
    }
    _actionController.add(action);
  }

  // Runs one action without awaiting it, so actions run concurrently, and
  // sends every error, sync or async, to [onError].
  void _run(A action) {
    try {
      final result = handleAction(action);
      if (result is Future<void>) result.catchError(_report);
    } catch (e, s) {
      _report(e, s);
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    onError(error, stackTrace);
  }

  /// Runs once per dispatched action. Actions are not awaited one after
  /// another: a second action starts while a first async one is still running.
  ///
  /// Subclasses MUST implement this method to define their specific logic
  /// for reacting to actions.
  @protected
  FutureOr<void> handleAction(A action);

  /// Receives every error thrown by [handleAction], sync or async, including
  /// one that completes after [dispose]. Default: forwards to the parent's
  /// [onError] when this controller has a parent (by [adopt] or by a [slot])
  /// and is not disposed; otherwise logs with `appLogger.error`. An error
  /// that arrives after this child was disposed is logged, never forwarded.
  /// Never rethrow from here.
  @protected
  void onError(Object error, StackTrace stackTrace) {
    final parent = _parent;
    if (parent != null && !_isDisposed) {
      parent.onError(error, stackTrace);
      return;
    }
    appLogger.error(
      'Unhandled error in $runtimeType action: $error',
      error,
      stackTrace,
    );
  }

  /// Makes this controller [child]'s parent and owns it: child is disposed
  /// with this controller (as by [own]). Returns [child]. After this
  /// controller is disposed, disposes [child] at once (as [own] does).
  /// Throws [StateError] when [child] is this controller or already has a
  /// parent.
  @protected
  C adopt<C extends Controller>(C child) {
    if (identical(child, this)) {
      throw StateError('A controller cannot adopt itself.');
    }
    if (child._parent != null) {
      throw StateError('Controller already has a parent.');
    }
    child._parent = this;
    own(child);
    return child;
  }

  /// A slot for zero or one keyed child at a time, released with this
  /// controller. Each child the slot creates has this controller as parent,
  /// but the slot, not this controller, disposes it.
  @protected
  ControllerSlot<K, C> slot<K, C extends Controller>(C Function(K key) create) {
    final slot = ControllerSlot<K, C>._(this, create);
    own(slot);
    return slot;
  }

  /// Listens to [stream] until dispose. Each event goes to [onData]; a sync
  /// or async throw from [onData], and an error event, go to [onError]. The
  /// subscription survives errors.
  @protected
  StreamSubscription<T> listenTo<T>(
    Stream<T> stream,
    FutureOr<void> Function(T event) onData,
  ) {
    final subscription = stream.listen(
      (event) {
        try {
          final result = onData(event);
          if (result is Future) {
            result.then<void>((_) {}, onError: _report);
          }
        } catch (e, s) {
          _report(e, s);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        onError(error, stackTrace);
      },
      cancelOnError: false,
    );
    return own(subscription);
  }

  /// Registers [resource] to be released by [dispose], and returns it.
  ///
  /// Accepted types and how each is released:
  /// - [Disposable]: `dispose()`
  /// - [AbstractControl] (FormGroup, FormControl, FormArray): `dispose()`
  /// - [StreamSubscription]: `cancel()`
  /// - [StreamController] (includes rxdart Subjects): `close()`
  /// - [Timer]: `cancel()`
  /// - [CompositeSubscription]: `dispose()`
  /// - [Controller]: `dispose()`
  /// - [ChangeNotifier] (TextEditingController, FocusNode, ...): `dispose()`
  /// - [ControllerSlot]: disposes the current child and closes the stream
  ///
  /// Any other type throws [ArgumentError]. Called after [dispose], it
  /// releases [resource] at once and returns it.
  @protected
  T own<T extends Object>(T resource) {
    final FutureOr<void> Function() release = switch (resource) {
      Disposable() => resource.dispose,
      AbstractControl() => resource.dispose,
      // CompositeSubscription is itself a StreamSubscription, so it goes first.
      CompositeSubscription() => resource.dispose,
      StreamSubscription() => resource.cancel,
      StreamController() => resource.close,
      Timer() => resource.cancel,
      Controller() => resource.dispose,
      ChangeNotifier() => resource.dispose,
      ControllerSlot() => resource._release,
      _ => throw ArgumentError.value(
        resource,
        'resource',
        'Cannot own a ${resource.runtimeType}: no known way to release it.',
      ),
    };
    if (_isDisposed) {
      _releaseOne(release);
    } else {
      _releasers.add(release);
    }
    return resource;
  }

  void _releaseOne(FutureOr<void> Function() release) {
    try {
      final result = release();
      if (result is Future<void>) result.catchError(_report);
    } catch (e, s) {
      _report(e, s);
    }
  }

  /// Adds [value] to [target] unless this controller is disposed or [target]
  /// is closed. Never throws for those two cases.
  @protected
  void emit<T>(StreamController<T> target, T value) {
    if (_isDisposed || target.isClosed) return;
    target.add(value);
  }

  /// Called once by the coordinator right after it creates this controller
  /// for [route], before its view is built. Override with a `covariant`
  /// parameter of your route type. Default: does nothing.
  void enter(covariant ConfigurationBase route) {}

  /// Whether [dispose] has been called.
  bool get isDisposed => _isDisposed;

  /// Cleans up controller resources. Idempotent.
  ///
  /// Releases owned resources in reverse order of [own] calls. An error
  /// thrown while releasing one goes to [onError]; the rest are still
  /// released. Subclasses overriding this method MUST call `super.dispose()`.
  @mustCallSuper
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _actionSubscription?.cancel();
    _actionSubscription = null;
    _actionController.close();

    for (final release in _releasers.reversed.toList()) {
      _releaseOne(release);
    }
    _releasers.clear();
  }
}
