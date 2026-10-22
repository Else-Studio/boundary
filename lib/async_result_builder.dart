import 'package:flutter/material.dart';

import 'utils.dart';

class AsyncResultBuilder<T> extends StatelessWidget {
  const AsyncResultBuilder({
    super.key,
    required this.stream,
    required this.data,
    this.loading,
    this.failure,
    this.empty,
  });

  final Stream<AsyncResult<T>> stream;
  final Widget Function(BuildContext context, T data) data;
  final WidgetBuilder? loading;
  final Widget Function(BuildContext context, Failure<T> failure)? failure;
  final WidgetBuilder? empty;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
