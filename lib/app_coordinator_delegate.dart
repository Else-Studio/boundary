import 'package:auto_injector/auto_injector.dart';

import 'route_table.dart';
import 'router.dart';
import 'service/post_auth_redirect_store.dart';

/// An abstract delegate responsible for parsing a URI into a concrete
/// [ConfigurationBase].
///
/// This decouples the [NavigationService] from application-specific routing logic.
abstract class NavigationServiceDelegate {
  ///
  /// Returns the application's default route for an authenticated user
  /// after they have logged in.
  ConfigurationBase getPostLoginDefaultRoute();

  /// Returns the application's primary login route.
  ConfigurationBase getLoginRoute();
}

/// An abstract delegate responsible for providing the application-specific
/// implementations required by the generic [AppCoordinator].
///
/// A concrete implementation of this class must be provided to the
/// [AppCoordinator] to wire up the application's unique services,
/// controllers, views, and routing logic.
abstract class AppCoordinatorDelegate extends NavigationServiceDelegate {
  /// Registers all application-specific services and controllers with the
  /// dependency [injector].
  void registerDependencies(AutoInjector injector);

  /// Every destination of the app, in match order.
  List<RouteBinding> get routes;

  /// Called once, in the AppCoordinator constructor, after services are
  /// registered. Guards run in list order.
  List<RouteGuard> createGuards(AutoInjector injector);

  /// The store NavigationService keeps the post-auth redirect in.
  PostAuthRedirectStore createPostAuthRedirectStore() =>
      InMemoryPostAuthRedirectStore();
}
