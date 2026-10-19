import 'package:flutter/material.dart';

import 'controller.dart';
import 'route_table.dart';
import 'router.dart';
import 'service/navigation_service.dart';

enum DefaultPageAction { back }

class DefaultPageController extends Controller<DefaultPageAction> {
  DefaultPageController(NavigationService navigationService);

  /// The route given to enter: an ErrorRoute or a NotFoundRoute.
  ConfigurationBase? get route => throw UnimplementedError('not implemented');

  @override
  void handleAction(DefaultPageAction action) {
    throw UnimplementedError('not implemented');
  }
}

/// Reads DefaultPageController with context.read. Title 'Something went
/// wrong', then the ErrorRoute's message, then a button 'Back' that
/// dispatches DefaultPageAction.back.
class DefaultErrorPage extends StatelessWidget {
  const DefaultErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    throw UnimplementedError('not implemented');
  }
}

/// Reads DefaultPageController with context.read. Title 'Page not found',
/// then the NotFoundRoute's originalUrl, then a button 'Back' that
/// dispatches DefaultPageAction.back.
class DefaultNotFoundPage extends StatelessWidget {
  const DefaultNotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    throw UnimplementedError('not implemented');
  }
}

final RouteBinding<ErrorRoute, DefaultPageController> defaultErrorRouteBinding =
    RouteBinding<ErrorRoute, DefaultPageController>(
  path: ErrorRoute.path,
  parse: (p) => throw UnimplementedError('not implemented'),
  controller: (i) => DefaultPageController(i.get<NavigationService>()),
  page: const DefaultErrorPage(),
);

final RouteBinding<NotFoundRoute, DefaultPageController>
    defaultNotFoundRouteBinding =
    RouteBinding<NotFoundRoute, DefaultPageController>(
  path: NotFoundRoute.path,
  parse: (p) => throw UnimplementedError('not implemented'),
  controller: (i) => DefaultPageController(i.get<NavigationService>()),
  page: const DefaultNotFoundPage(),
);
