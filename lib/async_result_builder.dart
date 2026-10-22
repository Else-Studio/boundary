import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import 'utils.dart';

class AsyncResultBuilder<T> extends StatefulWidget {
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
  State<AsyncResultBuilder<T>> createState() => _AsyncResultBuilderState<T>();
}

class _AsyncResultBuilderState<T> extends State<AsyncResultBuilder<T>> {
  StreamSubscription<AsyncResult<T>>? _subscription;
  AsyncResult<T>? _result;
  Object? _error;
  StackTrace? _errorStackTrace;

  @override
  void initState() {
    super.initState();
    _attach(widget.stream);
    _armFrame();
  }

  @override
  void didUpdateWidget(AsyncResultBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream) {
      _subscription?.cancel();
      _attach(widget.stream);
      _armFrame();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _attach(Stream<AsyncResult<T>> stream) {
    _error = null;
    _errorStackTrace = null;
    _result = _initialResult(stream);
    _subscription = stream.listen(
      (value) {
        if (!mounted) return;
        setState(() {
          _error = null;
          _errorStackTrace = null;
          _result = value;
        });
        _armFrame();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(() {
          _error = error;
          _errorStackTrace = stackTrace;
          _result = null;
        });
        _armFrame();
      },
    );
  }

  AsyncResult<T>? _initialResult(Stream<AsyncResult<T>> stream) {
    if (stream is ValueStream<AsyncResult<T>>) {
      return stream.valueOrNull;
    }
    return null;
  }

  /// Keeps one frame pending after the current one so a later async stream
  /// event can be built by a single [WidgetTester.pump].
  void _armFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        WidgetsBinding.instance.scheduleFrame();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      final failureResult = Failure<T>(
        _error!,
        stackTrace: _errorStackTrace,
      );
      return widget.failure?.call(context, failureResult) ??
          const Center(child: Text('Something went wrong.'));
    }

    final result = _result;
    if (result == null) {
      return widget.loading?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }

    return switch (result) {
      Loading() =>
        widget.loading?.call(context) ??
            const Center(child: CircularProgressIndicator()),
      Data(:final data) => widget.data(context, data),
      Failure() =>
        widget.failure?.call(context, result) ??
            const Center(child: Text('Something went wrong.')),
      Empty() => widget.empty?.call(context) ?? const SizedBox.shrink(),
    };
  }
}
