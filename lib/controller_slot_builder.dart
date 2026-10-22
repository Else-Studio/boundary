import 'package:flutter/widgets.dart';
import 'package:rxdart/rxdart.dart';

import 'controller.dart';

/// Builds the current child of a [ControllerSlot] under [Provider] and a key
/// that resets widget state when the child changes.
class ControllerSlotBuilder<C extends Controller> extends StatelessWidget {
  const ControllerSlotBuilder({
    super.key,
    required this.stream,
    required this.builder,
    this.empty,
  });

  final ValueStream<C?> stream;

  /// Built under `Provider<C>.value` and `KeyedSubtree(key: ObjectKey(c))`.
  final Widget Function(BuildContext context, C controller) builder;

  /// Shown when the slot is empty. Default: [SizedBox.shrink].
  final WidgetBuilder? empty;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
