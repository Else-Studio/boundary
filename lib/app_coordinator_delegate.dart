import 'package:auto_injector/auto_injector.dart';

import 'utils.dart';
import 'controller.dart';
import 'route_table.dart';
import 'router.dart';
import 'service/auth_service.dart';

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

  /// Determines whether the given [config] represents the authentication
  /// callback route.
  bool isAuthCallbackRoute(ConfigurationBase config);
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

  Controller? get shellController;

  /// Determines whether a given [controller] should be disposed when it's
  /// no longer the active controller.
  ///
  /// This is used to implement caching strategies, for instance, keeping
  /// controllers for main tabs alive on mobile platforms.
  bool shouldDisposeController(Controller? controller);

  /// Returns the application-specific route for the primary login/authentication screen.
  @override
  ConfigurationBase getLoginRoute();

  /// Returns the application-specific route for resetting a password.
  ConfigurationBase getResetPasswordRoute({String? email});

  /// Determines if a given route configuration is for a page that should only
  /// be accessible to unauthenticated users.
  ///
  /// This is used to redirect already-authenticated users away from pages
  /// like login or registration.
  bool isPublicOnlyRoute(ConfigurationBase config);

  bool isLogoutRoute(ConfigurationBase config);

  /// Resolves an authentication state into an application-specific route, if necessary.
  ///
  /// This method acts as a "hook" for the `AppCoordinator`. The coordinator
  /// calls this to allow the application to handle its own unique auth-related
  /// business logic (e.g., forcing a data policy page) before the coordinator
  /// applies its generic session handling logic.
  ///
  /// If the application handles the state, it should return a [ConfigurationBase].
  /// If it does not handle the state, it must return `null`, allowing the
  /// `AppCoordinator` to proceed with its default logic.
  ConfigurationBase? resolveAppSpecificAuthState(
    AsyncResult<User> authState,
    ConfigurationBase navRequest,
  );
}
