import 'dart:async';

import '../controller.dart';
import 'pump_event_queue.dart';

/// Runs a [Controller]'s actions to the end and records its streams.
class ControllerHarness<A, C extends Controller<A>> {
  ControllerHarness(this._controller);

  final C _controller;

  final List<StreamSubscription<Object?>> _recordings = [];

  C get controller => _controller;

  /// dispatch(action), then pumpEventQueue().
  Future<void> act(A action) async {
    _controller.dispatch(action);
    await pumpEventQueue();
  }

  /// Every event of [stream] from now on (a ValueStream's current value first).
  List<T> record<T>(Stream<T> stream) {
    final events = <T>[];
    _recordings.add(stream.listen(events.add));
    return events;
  }

  /// Cancels the recordings and disposes the controller.
  void dispose() {
    for (final recording in _recordings) {
      recording.cancel();
    }
    _recordings.clear();
    _controller.dispose();
  }
}
