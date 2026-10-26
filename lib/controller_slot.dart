part of 'controller.dart';

/// Zero or one keyed child at a time. Created by [Controller.slot]; the owner
/// releases it. There is no public dispose.
class ControllerSlot<K, C extends Controller> {
  ControllerSlot._(this._owner, this._create)
    : _controller = StreamController<C?>.broadcast(sync: true) {
    _stream = _SyncValueStream<C?>(
      controller: _controller,
      readValue: () => _current,
    );
  }

  final Controller _owner;
  final C Function(K key) _create;
  final StreamController<C?> _controller;
  late final ValueStream<C?> _stream;
  C? _current;
  K? _key;

  /// Synchronous: a listener runs inside [activate]/[clear]. Starts at null.
  ValueStream<C?> get stream => _stream;

  /// The current child, or null.
  C? get current => _current;

  /// The current child's key, or null.
  K? get key => _key;

  /// Same key as the current child: returns it and emits nothing.
  /// Otherwise: creates via the slot's create, with the owner as parent;
  /// emits the new child; then disposes the previous. Returns the child.
  /// Throws [StateError] once the owner is disposed.
  C activate(K key) {
    if (_owner.isDisposed || _controller.isClosed) {
      throw StateError('Cannot activate a slot after its owner is disposed.');
    }
    if (_key == key && _current != null) {
      return _current as C;
    }
    final previous = _current;
    final child = _create(key);
    child._parent = _owner;
    _key = key;
    _current = child;
    _controller.add(child);
    previous?.dispose();
    return child;
  }

  /// Emits null, then disposes the current child. Empty: does nothing.
  void clear() {
    final previous = _current;
    if (previous == null) return;
    _key = null;
    _current = null;
    _controller.add(null);
    previous.dispose();
  }

  /// Called by the owner's [Controller.own] release. Disposes the current
  /// child, then closes the stream without emitting null first.
  void _release() {
    final previous = _current;
    _key = null;
    _current = null;
    if (previous != null && !previous.isDisposed) {
      previous.dispose();
    }
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

/// A broadcast [ValueStream] that replays the current value to each new
/// listener and delivers [StreamController.broadcast] events synchronously.
class _SyncValueStream<T> extends Stream<T> implements ValueStream<T> {
  _SyncValueStream({
    required StreamController<T> controller,
    required T Function() readValue,
  }) : _controller = controller,
       _readValue = readValue;

  final StreamController<T> _controller;
  final T Function() _readValue;

  @override
  bool get isBroadcast => true;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (onData != null && !_controller.isClosed) {
      onData(_readValue());
    }
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  bool get hasValue => true;

  @override
  T get value => _readValue();

  @override
  T? get valueOrNull => _readValue();

  @override
  bool get hasError => false;

  @override
  Object get error => throw ValueStreamError.hasNoError();

  @override
  Object? get errorOrNull => null;

  @override
  StackTrace? get stackTrace => null;

  @override
  StreamNotification<T>? get lastEventOrNull =>
      StreamNotification.data(_readValue());
}
