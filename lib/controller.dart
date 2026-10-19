import 'dart:async';

import 'package:flutter/foundation.dart';

import 'utils.dart';

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

  // Holds external subscriptions (e.g., from services) managed by this controller.
  final List<StreamSubscription> _externalSubscriptions = [];

  Controller() {
    _actionController = StreamController<A>();
    _actionSubscription = _actionController.stream.listen(handleAction);
  }

  /// Dispatches an action [A] from the View to be processed by the controller.
  void dispatch(A action) {
    if (_actionController.isClosed) {
      appLogger.warning(
        'Attempted to dispatch action ($action) on a disposed controller ($runtimeType).',
      );
      return;
    }
    _actionController.add(action);
  }

  /// Handles the incoming [action] dispatched via the stream.
  ///
  /// Subclasses MUST implement this method to define their specific logic
  /// for reacting to actions.
  @protected
  FutureOr<void> handleAction(A action);

  /// Receives every error thrown by [handleAction], sync or async.
  @protected
  void onError(Object error, StackTrace stackTrace) {
    throw UnimplementedError('not implemented');
  }

  /// Registers [resource] to be released by [dispose], and returns it.
  @protected
  T own<T extends Object>(T resource) {
    throw UnimplementedError('not implemented');
  }

  /// Adds [value] to [target] unless this controller is disposed or [target]
  /// is closed.
  @protected
  void emit<T>(StreamController<T> target, T value) {
    throw UnimplementedError('not implemented');
  }

  /// Whether [dispose] has been called.
  bool get isDisposed => throw UnimplementedError('not implemented');

  /// Adds an external [sub]scription (e.g., from a service stream)
  /// to be automatically cancelled when this controller is disposed.
  @protected
  void addSubscription(StreamSubscription sub) {
    _externalSubscriptions.add(sub);
  }

  /// Cleans up controller resources.
  /// Subclasses overriding this method MUST call `super.dispose()`.
  @mustCallSuper
  void dispose() {
    _actionSubscription?.cancel();
    _actionSubscription = null;
    _actionController.close();

    for (final sub in _externalSubscriptions) {
      sub.cancel();
    }
    _externalSubscriptions.clear();
  }
}
