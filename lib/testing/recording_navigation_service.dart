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
        );

  /// Every route emitted on [routeRequestStream], in order (nulls left out).
  List<ConfigurationBase> get requests =>
      throw UnimplementedError('not implemented');

  /// Tells the service what the app shows.
  void show(ConfigurationBase? base, {ConfigurationBase? modal}) {
    throw UnimplementedError('not implemented');
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
