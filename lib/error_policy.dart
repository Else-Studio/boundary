import 'package:flutter/foundation.dart' show protected;

import 'controller.dart';
import 'notice.dart';
import 'router.dart';
import 'service/navigation_service.dart';

class ErrorPolicy {
  ErrorPolicy(this.notices, this.navigation);

  final NoticeService notices;
  final NavigationService navigation;

  /// English text for inline display. Override for other texts.
  String messageFor(Object error) =>
      throw UnimplementedError('not implemented');

  /// warning for RateLimitExceededException, error otherwise.
  NoticeLevel levelFor(Object error) =>
      throw UnimplementedError('not implemented');

  /// A page to show for [error]. Default: null for every error.
  ConfigurationBase? pageFor(Object error) => null;

  /// Triages [error] into a notice, a page, or nothing.
  void handle(Object error, [StackTrace? stackTrace]) =>
      throw UnimplementedError('not implemented');
}

/// A controller whose errors go through [errorPolicy].
mixin PolicyErrors<A> on Controller<A> {
  ErrorPolicy get errorPolicy;

  @override
  @protected
  void onError(Object error, StackTrace stackTrace) =>
      errorPolicy.handle(error, stackTrace);
}
