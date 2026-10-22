import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

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
  Widget build(BuildContext context) {
    return StreamBuilder<AsyncResult<T>>(
      stream: stream,
      initialData: stream is ValueStream<AsyncResult<T>>
          ? (stream as ValueStream<AsyncResult<T>>).valueOrNull
          : null,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final failureResult = Failure<T>(
            snapshot.error!,
            stackTrace: snapshot.stackTrace,
          );
          return failure?.call(context, failureResult) ??
              const Center(child: Text('Something went wrong.'));
        }

        final result = snapshot.data;
        if (result == null) {
          return loading?.call(context) ??
              const Center(child: CircularProgressIndicator());
        }

        return switch (result) {
          Loading() =>
            loading?.call(context) ??
                const Center(child: CircularProgressIndicator()),
          Data(:final data) => this.data(context, data),
          Failure() =>
            failure?.call(context, result) ??
                const Center(child: Text('Something went wrong.')),
          Empty() => empty?.call(context) ?? const SizedBox.shrink(),
        };
      },
    );
  }
}
