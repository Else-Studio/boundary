import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controller.dart';
import 'route_table.dart';
import 'router.dart';
import 'service/navigation_service.dart';

enum DefaultPageAction { back }

class DefaultPageController extends Controller<DefaultPageAction> {
  DefaultPageController(this._navigationService);

  final NavigationService _navigationService;
  ConfigurationBase? _route;

  /// The route given to enter: an ErrorRoute or a NotFoundRoute.
  ConfigurationBase? get route => _route;

  @override
  void enter(ConfigurationBase route) {
    _route = route;
  }

  @override
  void handleAction(DefaultPageAction action) {
    switch (action) {
      case DefaultPageAction.back:
        _navigationService.navigateBackOrLogin();
    }
  }
}

Widget _defaultPage(BuildContext context, String title, String detail) {
  final controller = context.read<DefaultPageController>();
  return Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(detail),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => controller.dispatch(DefaultPageAction.back),
            child: const Text('Back'),
          ),
        ],
      ),
    ),
  );
}

/// Reads DefaultPageController with context.read. Title 'Something went
/// wrong', then the ErrorRoute's message, then a button 'Back' that
/// dispatches DefaultPageAction.back.
class DefaultErrorPage extends StatelessWidget {
  const DefaultErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final route = context.read<DefaultPageController>().route;
    return _defaultPage(
      context,
      'Something went wrong',
      route is ErrorRoute ? route.message : '',
    );
  }
}

/// Reads DefaultPageController with context.read. Title 'Page not found',
/// then the NotFoundRoute's originalUrl, then a button 'Back' that
/// dispatches DefaultPageAction.back.
class DefaultNotFoundPage extends StatelessWidget {
  const DefaultNotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final route = context.read<DefaultPageController>().route;
    return _defaultPage(
      context,
      'Page not found',
      route is NotFoundRoute ? route.originalUrl : '',
    );
  }
}

final RouteBinding<ErrorRoute, DefaultPageController> defaultErrorRouteBinding =
    RouteBinding<ErrorRoute, DefaultPageController>(
  path: ErrorRoute.path,
  parse: (p) => ErrorRoute(
    message: p['message'] ?? '',
    isSessionTermination: p['isSessionTermination'] == 'true',
  ),
  controller: (i) => DefaultPageController(i.get<NavigationService>()),
  page: const DefaultErrorPage(),
  access: RouteAccess.public,
);

final RouteBinding<NotFoundRoute, DefaultPageController>
    defaultNotFoundRouteBinding =
    RouteBinding<NotFoundRoute, DefaultPageController>(
  path: NotFoundRoute.path,
  parse: (p) => const NotFoundRoute(NotFoundRoute.path),
  controller: (i) => DefaultPageController(i.get<NavigationService>()),
  page: const DefaultNotFoundPage(),
  access: RouteAccess.public,
);
