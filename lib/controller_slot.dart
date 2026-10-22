import 'package:rxdart/rxdart.dart';

import 'controller.dart';

/// Zero or one keyed child at a time. Created by [Controller.slot]; the owner
/// releases it. There is no public dispose.
class ControllerSlot<K, C extends Controller> {
  /// Synchronous ([BehaviorSubject.seeded] with `sync: true`): a listener runs
  /// inside [activate]/[clear]. Starts at null.
  ValueStream<C?> get stream => throw UnimplementedError('not implemented');

  C? get current => throw UnimplementedError('not implemented');

  K? get key => throw UnimplementedError('not implemented');

  /// Same key as the current child: returns it and emits nothing.
  /// Otherwise: creates via the slot's create, with the owner as parent;
  /// emits the new child; then disposes the previous. Returns the child.
  /// Throws [StateError] once the owner is disposed.
  C activate(K key) => throw UnimplementedError('not implemented');

  /// Emits null, then disposes the current child. Empty: does nothing.
  void clear() => throw UnimplementedError('not implemented');
}
