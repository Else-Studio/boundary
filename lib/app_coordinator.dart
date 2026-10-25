import 'package:auto_injector/auto_injector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:rxdart/rxdart.dart';

import 'app_coordinator_delegate.dart';
import 'controller.dart';
import 'model/error_models.dart';
import 'notice.dart';
import 'route_table.dart';
import 'router.dart';
import 'service/auth_service.dart';
import 'service/http_service.dart';
import 'service/navigation_service.dart';
import 'utils.dart';

class AppCoordinator extends ChangeNotifier {
  final _logger = useLogger('ApCo');
  final AutoInjector injector;
  final AppCoordinatorDelegate _delegate;

  ConfigurationBase? _baseConfiguration;
  ConfigurationBase? _modalConfiguration;
  Controller? _baseController;
  Controller? _fallbackController;
  Controller? _modalController;
  LayoutBinding? _layout;
  Controller? _layoutController;

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

  /// The controller of the current base route's layout, or null.
  Controller? get layoutController => _layoutController;

  /// Built once in the constructor from delegate.routes, before any service
  /// is registered.
  late final RouteTable routeTable;

  /// Created once in the constructor, in the order the delegate gives them.
  late final List<RouteGuard> _guards;

  AppCoordinator(this._delegate, {AutoInjector? injector})
      : injector = injector ?? AutoInjector() {
    routeTable = RouteTable(_delegate.routes);
    // If an injector was NOT passed in, we are in production.
    // Create our own injector and set everything up immediately.
    if (injector == null) {
      _setupServicesAndControllers();
    }
    _guards = _delegate.createGuards(this.injector);
    _setupListeners();
    authService.initialize();
  }
  void _setupServicesAndControllers() {
    injector.addSingleton(() => NoticeService());
    injector.addSingleton(
        () => NavigationService(
              delegate: _delegate,
              routes: routeTable,
              redirectStore: _delegate.createPostAuthRedirectStore(),
            ));
    injector.addSingleton(
      () => _delegate.createErrorPolicy(
        injector.get<NoticeService>(),
        injector.get<NavigationService>(),
      ),
    );
    injector.addSingleton<BaseClient>(Client.new);
    injector.addSingleton<HttpService>(() =>
        HttpService(injector.get<AuthService>(), injector.get<BaseClient>()));

    _delegate.registerDependencies(injector);

    injector.commit();
    _logger.info("AppCoordinator services and controllers initialized.");
  }

  void _setupListeners() {
    CombineLatestStream.combine2(
      authService.authState,
      navigationService.routeRequestStream.whereNotNull(),
      (AuthState authState, ConfigurationBase navRequest) => (
        auth: authState as Object,
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
          Failure<Object>(e, stackTrace: s),
          _baseConfiguration ?? _delegate.getLoginRoute(),
        );
      },
    ).addTo(_compositeSubscription);
    _logger.info("AppCoordinator listeners set up.");
  }

  void _queueReconcile(
    Object authState,
    ConfigurationBase navRequest,
  ) {
    if (_isDisposed) return;
    _reconcileTail = _reconcileTail.then(
      (_) => _isDisposed ? null : _reconcileSafely(authState, navRequest),
    );
  }

  Future<void> _reconcileSafely(
    Object authState,
    ConfigurationBase navRequest,
  ) async {
    if (_isDisposed) return;
    try {
      await _reconcileState(authState, navRequest);
    } catch (error, stackTrace) {
      _logger.error("State reconciliation failed", error, stackTrace);
    }
  }

  static const _maxGuardRedirects = 5;

  /// Resolves (auth, request) to the route to show, or null for "no state
  /// change".
  Future<ConfigurationBase?> _resolve(
    Object authState,
    ConfigurationBase navRequest,
  ) async {
    final state = authState is AuthState ? authState : null;
    if (state is AuthUnknown) {
      _logger.info(
        "Auth state is unknown. Preserving nav request to avoid state loss during auth.",
      );
      return navRequest;
    }

    final isSignedIn = state is Authenticated;
    var candidate = navRequest;

    if (authState is Failure) {
      _logger.error("Auth state error: ${authState.error}");
      return ErrorRoute(
        isSessionTermination: true,
        message: 'The session could not be checked.',
        problem: HttpProblem(
          title: 'Auth state error',
          detail: authState.error.toString(),
        ),
      );
    } else if (isSignedIn) {
      final postAuthDestination =
          await navigationService.consumePostAuthRedirect();
      if (_isDisposed) return null;
      if (postAuthDestination != null) {
        _logger.info(
          "Post-authentication redirect found. Navigating to ${postAuthDestination.runtimeType}",
        );
        candidate = postAuthDestination;
      }
    }

    var redirects = 0;
    while (true) {
      // Access step.
      final access = routeTable.bindingFor(candidate).access;
      if (isSignedIn) {
        if (access == RouteAccess.guestOnly) {
          _logger.info(
            "Authenticated: ${candidate.runtimeType} is guest-only. Redirecting to default.",
          );
          candidate = _delegate.getPostLoginDefaultRoute();
        }
        if (candidate.isRoot) {
          _logger.info(
            "Authenticated: Root requested. Going to post login route",
          );
          candidate = _delegate.getPostLoginDefaultRoute();
        }
      } else if (access == RouteAccess.protected) {
        if (state is SignedOut && state.reason == SignedOutReason.signedOut) {
          _logger.info("Signed out by the user. Navigating...");
          navigationService.redirectTo(_delegate.getLoginRoute());
          return null;
        }
        _logger.info(
          "Protected route ${candidate.runtimeType} requested. Storing for post-auth redirect.",
        );
        await navigationService.setPostAuthRedirect(candidate);
        if (_isDisposed) return null;
        candidate = _delegate.getLoginRoute();
      }

      // Guard step.
      GuardRedirect? redirect;
      for (final guard in _guards) {
        try {
          final result = await guard.check(candidate);
          if (result is GuardRedirect) {
            redirect = result;
            break;
          }
        } catch (error, stackTrace) {
          _logger.error(
            "Route guard failed for ${candidate.runtimeType}",
            error,
            stackTrace,
          );
          return const ErrorRoute(message: 'A page check failed.');
        }
        if (_isDisposed) return null;
      }
      if (redirect == null) return candidate;

      redirects++;
      if (redirects > _maxGuardRedirects) {
        _logger.error("Route guards redirected more than $_maxGuardRedirects "
            "times; last candidate ${candidate.runtimeType}");
        return const ErrorRoute(message: 'Opening that page kept redirecting.');
      }
      candidate = redirect.route;
    }
  }

  Future<void> _reconcileState(
    Object authState,
    ConfigurationBase navRequest,
  ) async {
    if (_isDisposed) return;
    _logger.debug(
      "Reconciling state. Auth: ${authState.runtimeType}, NavRequest: ${navRequest.runtimeType}",
    );

    final determinedConfig = await _resolve(authState, navRequest);
    // null: no state change (the signed out + protected row), or disposed.
    if (determinedConfig == null) return;
    if (_isDisposed) return;

    ConfigurationBase? nextBaseConfig;
    ConfigurationBase? nextModalConfig;

    bool isRequestingModal = determinedConfig.isModal;

    if (isRequestingModal) {
      nextBaseConfig = _baseConfiguration;
      if (nextBaseConfig == null && authState is! AuthUnknown) {
        nextBaseConfig = determinedConfig.defaultBaseRoute ??
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
        _updateLayout(nextBaseConfig);
        if (!_updateInPlace(oldBaseController, oldBaseConfig, nextBaseConfig)) {
          if (oldBaseController != null) {
            _disposeControllerAfterRouteUpdate(oldBaseController);
          }
          _baseController = _baseConfiguration != null
              ? _createController(_baseConfiguration!)
              : null;
        }
        final fallback = _fallbackController;
        if (fallback != null && _baseController != null) {
          _fallbackController = null;
          _disposeControllerAfterRouteUpdate(fallback);
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

  /// Keeps the layout controller while [next] shares the current layout.
  /// Otherwise disposes it and creates the new layout's controller.
  void _updateLayout(ConfigurationBase? next) {
    final nextLayout = next == null ? null : routeTable.bindingFor(next).layout;
    if (identical(nextLayout, _layout)) return;
    final old = _layoutController;
    if (old != null) _disposeControllerAfterRouteUpdate(old);
    _layout = nextLayout;
    _layoutController = nextLayout?.createController(injector);
  }

  /// Calls [RouteUpdatable.update] when [controller] stays for a route of the
  /// same type with other params. Returns whether it did.
  bool _updateInPlace(
    Controller? controller,
    ConfigurationBase? current,
    ConfigurationBase? next,
  ) {
    if (controller is! RouteUpdatable ||
        current == null ||
        next == null ||
        current.runtimeType != next.runtimeType) {
      return false;
    }
    (controller as RouteUpdatable).update(next);
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
    // Without a scheduled frame the callback would wait for the next one.
    binding.ensureVisualUpdate();
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
      if (authService.authState.value is AuthUnknown) {
        return const Scaffold(
          key: ValueKey('AppCoordinatorLoadingBase-Generic'),
          body: Center(child: CircularProgressIndicator()),
        );
      }
      const route = ErrorRoute(
        message: 'The app could not decide which page to show.',
        problem: HttpProblem(
          title: 'Application State Error',
          detail:
              "Application state could not be determined (no base controller).",
        ),
      );
      final fallback = _fallbackController ??= _createController(route);
      return routeTable.bindingFor(route).buildView(fallback);
    }
    final binding = routeTable.bindingFor(_baseConfiguration!);
    final page = binding.buildView(_baseController!);
    final layout = binding.layout;
    final layoutController = _layoutController;
    if (layout == null || layoutController == null) return page;
    return layout.wrap(layoutController, page);
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
    _fallbackController?.dispose();
    _modalController?.dispose();
    for (final controller in _pendingControllerDisposals) {
      controller.dispose();
    }
    _pendingControllerDisposals.clear();
    _layoutController?.dispose();

    injector.dispose();
    super.dispose();
  }
}
