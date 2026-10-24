import 'dart:async';

import '../app_coordinator_delegate.dart';
import '../route_table.dart';
import '../router.dart';
import '../service/navigation_service.dart';

/// A real [NavigationService] that records every request it emits.
class RecordingNavigationService extends NavigationService {
  RecordingNavigationService({
    required ConfigurationBase loginRoute,
    required ConfigurationBase homeRoute,
    List<RouteBinding> routes = const [],
  }) : super(
          delegate: _RecordingDelegate(loginRoute, homeRoute),
          routes: RouteTable(routes),
        ) {
    _subscription = routeRequestStream.listen((route) {
      if (route == null) return;
      _requests.add(route);
    });
  }

  final List<ConfigurationBase> _requests = [];
  late final StreamSubscription<ConfigurationBase?> _subscription;

  /// Every route emitted on [routeRequestStream], in order (nulls left out).
  List<ConfigurationBase> get requests => List.unmodifiable(_requests);

  /// Tells the service what the app shows.
  void show(ConfigurationBase? base, {ConfigurationBase? modal}) {
    onRouteResolved(base: base, modal: modal);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class _RecordingDelegate implements NavigationServiceDelegate {
  const _RecordingDelegate(this.loginRoute, this.homeRoute);

  final ConfigurationBase loginRoute;
  final ConfigurationBase homeRoute;

  @override
  ConfigurationBase getLoginRoute() => loginRoute;

  @override
  ConfigurationBase getPostLoginDefaultRoute() => homeRoute;
}
