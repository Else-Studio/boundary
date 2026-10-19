import 'package:auto_injector/auto_injector.dart';
import 'package:flutter/material.dart' hide RouteAware;
import 'package:http/http.dart';
import 'package:rxdart/rxdart.dart';

import 'app_coordinator_delegate.dart';
import 'controller.dart';
import 'model/error_models.dart';
import 'route_table.dart';
import 'router.dart';
import 'service/auth_service.dart';
import 'service/http_service.dart';
import 'service/navigation_service.dart';
import 'utils.dart';

// Import ShellController to add getter

class AppCoordinator extends ChangeNotifier {
  final _logger = useLogger('ApCo');
  final AutoInjector injector;
  final AppCoordinatorDelegate _delegate;

  ConfigurationBase? _baseConfiguration;
  ConfigurationBase? _modalConfiguration;
  Controller? _baseController;
  Controller? _modalController;

  final Map<Type, Controller> _longLivedControllerCache = {};
  final Set<Controller> _pendingControllerDisposals = {};

  final _compositeSubscription = CompositeSubscription();
  Future<void> _reconcileTail = Future<void>.value();
  bool _isDisposed = false;

  Controller? get modalController => _modalController;

  ConfigurationBase? get baseConfiguration => _baseConfiguration;
  ConfigurationBase? get modalConfiguration => _modalConfiguration;
  ConfigurationBase? get currentTopConfiguration =>
      _modalConfiguration ?? _baseConfiguration;

  NavigationService get navigationService => injector.get<NavigationService>();
  AuthService get authService => injector.get<AuthService>();

  // Add getter for ShellController
  Controller? get shellController => _delegate.shellController;

  /// Built once in the constructor from delegate.routes, before any service
  /// is registered.
  late final RouteTable routeTable;

  AppCoordinator(this._delegate, {AutoInjector? injector})
      : injector = injector ?? AutoInjector() {
    routeTable = RouteTable(_delegate.routes);
    // If an injector was NOT passed in, we are in production.
    // Create our own injector and set everything up immediately.
    if (injector == null) {
      _setupServicesAndControllers();
    }
    _setupListeners();
    authService.initialize();
  }
  void _setupServicesAndControllers() {
    injector.addSingleton(
        () => NavigationService(delegate: _delegate, routes: routeTable));
    injector.addSingleton<BaseClient>(Client.new);
    injector.addSingleton(HttpService.new);

    _delegate.registerDependencies(injector);

    injector.commit();
    _logger.info("AppCoordinator services and controllers initialized.");
  }

  void _setupListeners() {
    CombineLatestStream.combine2(
      authService.userStream,
      navigationService.routeRequestStream.whereNotNull(),
      (AsyncResult<User> authState, ConfigurationBase navRequest) => (
        auth: authState,
        nav: navRequest,
      ),
    ).distinct().listen(
      (stateTuple) {
        _logger.verbose(
          "Combined Stream Listener triggered. Auth: ${stateTuple.auth.runtimeType}, NavRequest: ${stateTuple.nav.runtimeType}",
        );
        _queueReconcile(stateTuple.auth, stateTuple.nav);
      },
      onError: (e, s) {
        _logger.error("Error in combined navigation/auth stream", e, s);
        _queueReconcile(
          Failure(e, stackTrace: s),
          _baseConfiguration ?? _delegate.getLoginRoute(),
        );
      },
    ).addTo(_compositeSubscription);
    _logger.info("AppCoordinator listeners set up.");
  }

  void _queueReconcile(
    AsyncResult<User> authState,
    ConfigurationBase navRequest,
  ) {
    if (_isDisposed) return;
    _reconcileTail = _reconcileTail.then(
      (_) => _isDisposed ? null : _reconcileSafely(authState, navRequest),
    );
  }

  Future<void> _reconcileSafely(
    AsyncResult<User> authState,
    ConfigurationBase navRequest,
  ) async {
    if (_isDisposed) return;
    try {
      await _reconcileState(authState, navRequest);
    } catch (error, stackTrace) {
      _logger.error("State reconciliation failed", error, stackTrace);
    }
  }

  Future<void> _reconcileState(
    AsyncResult<User> authState,
    ConfigurationBase navRequest,
  ) async {
    if (_isDisposed) return;
    _logger.debug(
      "Reconciling state. Auth: ${authState.runtimeType}, NavRequest: ${navRequest.runtimeType}",
    );

    ConfigurationBase? determinedConfig;

    // Phase 1: Give the application-specific delegate the first chance to handle the state.
    final ConfigurationBase? appSpecificRoute = null;

    if (appSpecificRoute != null) {
      _logger.info(
        "Delegate handled auth state, determined route: ${appSpecificRoute.runtimeType}",
      );
      determinedConfig = appSpecificRoute;
    }
    // Phase 2: If the delegate didn't handle it, apply generic framework logic.
    else if (authState is Loading<User>) {
      _logger.info(
        "Auth state is Loading. Preserving nav request to avoid state loss during auth.",
      );
      determinedConfig = navRequest;
    } else if (authState is Failure<User>) {
      final error = authState.error;
      _logger.info("Auth state is Failure: ${error.runtimeType}");

      switch (error) {
        case LoggedOut():
          _logger.info("LoggedOut state detected. Navigating...");

          // If we are currently on the logout route, we should NOT navigate away.
          // The LogoutController is responsible for the final redirect to the
          // authentication server (e.g., Keycloak).
          if (false) {
            _logger.info(
              "LoggedOut state detected while on LogoutRoute. Letting the controller handle the final redirect.",
            );
            determinedConfig = navRequest;
          } else {
            authService.clearLoggedOutStateAndPrepareForPolicyCheck();

            navigationService.navigateTo(_delegate.getLoginRoute());
            return;
          }
          break;
        case NoSessionStored():
        case SessionExpired():
          _logger.info(
            "No session or session expired (${error.runtimeType}). NavRequest: ${navRequest.runtimeType}",
          );

          if (true) {
            _logger.info(
              "Protected route ${navRequest.runtimeType} requested. Storing for post-auth redirect.",
            );
            await navigationService.setPostAuthRedirect(navRequest);
            if (_isDisposed) return;
            determinedConfig = _delegate.getLoginRoute();
          } else {
            _logger.info(
              "Unprotected route ${navRequest.runtimeType} requested. Allowing.",
            );
            determinedConfig = navRequest;
          }
          break;
        default:
          _logger.error(
            "Unhandled AuthError: ${error.runtimeType}. Showing generic error.",
          );
          determinedConfig = ErrorRoute(
            isSessionTermination: true,
            message: 'error.session.unexpected',
            problem: HttpProblem(
              title: 'Unhandled AuthError',
              detail: error.toString(),
            ),
          );
      }
    } else if (authState is Data<User>) {
      _logger.info(
        "User is Authenticated. NavRequest: ${navRequest.runtimeType}",
      );
      final postAuthDestination =
          await navigationService.consumePostAuthRedirect();
      if (_isDisposed) return;

      if (postAuthDestination != null) {
        _logger.info(
          "Post-authentication redirect found. Navigating to ${postAuthDestination.runtimeType}",
        );
        determinedConfig = postAuthDestination;
      }
      // Delegate handles what happens if an authenticated user lands on a page
      // they shouldn't be on (like login).
      else if (false) {
        _logger.info(
          "Authenticated: navRequest was ${navRequest.runtimeType} (a public-only route). Redirecting to default.",
        );
        determinedConfig = _delegate.getPostLoginDefaultRoute();
      } else if (false) {
        _logger.info("Authenticated: LogoutRoute requested. Allowing.");
        determinedConfig = navRequest;
      } else if (navRequest.isRoot) {
        _logger.info(
          "Authenticated: Root requested. Going to post login route",
        );
        determinedConfig = _delegate.getPostLoginDefaultRoute();
      } else {
        _logger.info(
          "Authenticated: Allowed route ${navRequest.runtimeType} requested.",
        );
        determinedConfig = navRequest;
      }
    }

    if (_isDisposed) return;

    ConfigurationBase? nextBaseConfig;
    ConfigurationBase? nextModalConfig;

    bool isRequestingModal = determinedConfig?.isModal ?? false;

    if (isRequestingModal) {
      nextBaseConfig = _baseConfiguration;
      if (nextBaseConfig == null && authState is! Loading) {
        nextBaseConfig = determinedConfig?.defaultBaseRoute ??
            _delegate.getPostLoginDefaultRoute();

        // Sync the scaffolded base back to the navigation service so "Close" works correctly.
        navigationService.syncBaseConfiguration(nextBaseConfig);
      }
      nextModalConfig = determinedConfig;
    } else {
      nextModalConfig = null;
      nextBaseConfig = determinedConfig;
    }

    if (_isDisposed) return;
    if (nextBaseConfig != _baseConfiguration ||
        nextModalConfig != _modalConfiguration) {
      _logger.info(
        "Effective configuration changed. OldBase: ${_baseConfiguration?.runtimeType}, NewBase: ${nextBaseConfig?.runtimeType}. OldModal: ${_modalConfiguration?.runtimeType}, NewModal: ${nextModalConfig?.runtimeType}",
      );

      Controller? oldBaseController = _baseController;
      Controller? oldModalController = _modalController;
      final oldBaseConfig = _baseConfiguration;
      final oldModalConfig = _modalConfiguration;
      bool baseConfigChanged = nextBaseConfig != _baseConfiguration;
      bool modalConfigChanged = nextModalConfig != _modalConfiguration;

      _baseConfiguration = nextBaseConfig;
      _modalConfiguration = nextModalConfig;

      if (baseConfigChanged) {
        if (!_updateInPlace(oldBaseController, oldBaseConfig, nextBaseConfig)) {
          if (oldBaseController != null &&
              _delegate.shouldDisposeController(oldBaseController)) {
            _disposeControllerAfterRouteUpdate(oldBaseController);
          }
          _baseController = _baseConfiguration != null
              ? _createController(_baseConfiguration!)
              : null;
        }
      }

      if (modalConfigChanged) {
        if (!_updateInPlace(
            oldModalController, oldModalConfig, nextModalConfig)) {
          if (oldModalController != null) {
            _disposeControllerAfterRouteUpdate(oldModalController);
          }
          _modalController = _modalConfiguration != null
              ? _createController(_modalConfiguration!)
              : null;
        }
      }
      navigationService.onRouteResolved(
        base: _baseConfiguration,
        modal: _modalConfiguration,
      );
      notifyListeners();
    }
  }

  /// Calls [RouteAware.update] when [controller] stays for a route of the
  /// same type with other params. Returns whether it did.
  bool _updateInPlace(
    Controller? controller,
    ConfigurationBase? current,
    ConfigurationBase? next,
  ) {
    if (controller is! RouteAware ||
        current == null ||
        next == null ||
        current.runtimeType != next.runtimeType) {
      return false;
    }
    (controller as RouteAware).update(next);
    return true;
  }

  Controller _createController(ConfigurationBase route) =>
      routeTable.bindingFor(route).createController(injector, route);

  void _disposeControllerAfterRouteUpdate(Controller controller) {
    if (!_pendingControllerDisposals.add(controller)) return;
    final binding = _widgetsBindingOrNull();
    if (binding == null) {
      _pendingControllerDisposals.remove(controller);
      controller.dispose();
      return;
    }
    binding.addPostFrameCallback((_) {
      if (!_pendingControllerDisposals.remove(controller)) return;
      controller.dispose();
    });
  }

  WidgetsBinding? _widgetsBindingOrNull() {
    try {
      return WidgetsBinding.instance;
    } on FlutterError {
      return null;
    }
  }

  Widget getBaseContentWidget() {
    if (_baseController == null) {
      if (authService.isLoading ||
          (_baseConfiguration == null &&
              authService.userStream.value is Loading<User>)) {
        return const Scaffold(
          key: ValueKey('AppCoordinatorLoadingBase-Generic'),
          body: Center(child: CircularProgressIndicator()),
        );
      }
      const route = ErrorRoute(
        message: 'error.app.noState',
        problem: HttpProblem(
          title: 'Application State Error',
          detail:
              "Application state could not be determined (no base controller).",
        ),
      );
      return routeTable.bindingFor(route).buildView(_createController(route));
    }
    return routeTable
        .bindingFor(_baseConfiguration!)
        .buildView(_baseController!);
  }

  Widget? getModalContentWidget() {
    if (_modalConfiguration == null || _modalController == null) {
      return null;
    }
    return routeTable
        .bindingFor(_modalConfiguration!)
        .buildView(_modalController!);
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _logger.verbose('Disposing AppCoordinator');
    _compositeSubscription.dispose();

    _baseController?.dispose();
    _modalController?.dispose();
    for (final controller in _pendingControllerDisposals) {
      controller.dispose();
    }
    _pendingControllerDisposals.clear();
    for (var c in _longLivedControllerCache.values) {
      c.dispose();
    }
    _longLivedControllerCache.clear();

    injector.dispose();
    super.dispose();
  }
}
