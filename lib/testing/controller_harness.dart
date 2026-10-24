import '../controller.dart';

/// Runs a [Controller]'s actions to the end and records its streams.
class ControllerHarness<A, C extends Controller<A>> {
  ControllerHarness(this._controller);

  final C _controller;

  C get controller => _controller;

  /// dispatch(action), then pumpEventQueue().
  Future<void> act(A action) => throw UnimplementedError('not implemented');

  /// Every event of [stream] from now on (a ValueStream's current value first).
  List<T> record<T>(Stream<T> stream) =>
      throw UnimplementedError('not implemented');

  /// Cancels the recordings and disposes the controller.
  void dispose() => throw UnimplementedError('not implemented');
}
