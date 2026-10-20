import 'package:rxdart/rxdart.dart';

import '../route_table.dart';
import '../router.dart';
import '../utils.dart';
import '../app_coordinator_delegate.dart';
import 'post_auth_redirect_store.dart';

/// Captures navigation requests (intentions) and emits the requested route configuration.
class NavigationService {
  final _logger = useLogger('NavS');
  final NavigationServiceDelegate _delegate;
  final RouteTable _routes;

  final PostAuthRedirectStore _redirectStore;

  final _routeRequest$ = BehaviorSubject<ConfigurationBase?>();
  final _baseRoute$ = BehaviorSubject<ConfigurationBase?>.seeded(null);
  final _modalRoute$ = BehaviorSubject<ConfigurationBase?>.seeded(null);
  ConfigurationBase? _lastBaseConfiguration;

  ValueStream<ConfigurationBase?> get routeRequestStream =>
      _routeRequest$.stream;
  ConfigurationBase? get currentRequestedConfiguration =>
      _routeRequest$.valueOrNull;

  /// The base route the app shows, after redirects. Starts at null.
  ValueStream<ConfigurationBase?> get baseRouteStream => _baseRoute$.stream;

  /// The modal route shown, or null. Starts at null.
  ValueStream<ConfigurationBase?> get modalRouteStream => _modalRoute$.stream;

  /// Called by AppCoordinator only, each time what it shows changes. Each
  /// stream emits only when its value changed.
  void onRouteResolved({
    required ConfigurationBase? base,
    required ConfigurationBase? modal,
  }) {
    if (_baseRoute$.value != base) _baseRoute$.add(base);
    if (_modalRoute$.value != modal) _modalRoute$.add(modal);
  }

  NavigationService({
    required NavigationServiceDelegate delegate,
    required RouteTable routes,
    PostAuthRedirectStore? redirectStore,
  })  : _delegate = delegate,
        _routes = routes,
        _redirectStore = redirectStore ?? InMemoryPostAuthRedirectStore() {
    _logger.verbose(
      "NavigationService initialized with ${_routes.bindings.length} routes",
    );
  }

  /// Keeps [configuration]'s URI in the redirect store, so a navigation
  /// request can survive sign-in.
  Future<void> setPostAuthRedirect(ConfigurationBase configuration) async {
    await _redirectStore.save(configuration.uri);
    _logger.info('Saved post-auth redirect intent: ${configuration.uri}');
  }

  /// Takes the saved redirect, once, and parses it with the route table.
  /// Returns null when nothing is saved or the saved route is the home path.
  Future<ConfigurationBase?> consumePostAuthRedirect() async {
    final uri = await _redirectStore.take();
    if (uri == null) return null;
    if (uri.path == '/') {
      _logger.info('Attempted to go HomeRoute from Post login flow');
      return null;
    }
    _logger.info('Found post-auth redirect to: $uri');
    return _routes.parse(uri);
  }

  /// Forgets any saved post-authentication redirect. Call it on sign-out.
  Future<void> clearPostAuthRedirect() async {
    await _redirectStore.clear();
    _logger.info('Cleared post-authentication redirect intent.');
  }

  void retryLastNavigation() {
    _logger.debug("Request received to retry last navigation.");
    dismissModal();
  }

  void navigateTo(ConfigurationBase configuration) {
    _logger.debug(
      "Request received to navigate to: ${configuration.runtimeType}",
    );
    _processRequest(configuration);
  }

  void routerSetNewPath(ConfigurationBase configuration) {
    _logger.debug(
      "Platform requested navigation path: ${configuration.runtimeType}",
    );
    _processRequest(configuration);
  }

  /// Manually synchronizes the internal tracking of the "last base" configuration.
  /// This is used during deep-linking when the AppCoordinator scaffolds a background
  /// route that wasn't explicitly requested through the NavigationService.
  void syncBaseConfiguration(ConfigurationBase configuration) {
    if (configuration.isModal ||
        configuration is ErrorRoute ||
        _routes.isTransient(configuration)) {
      return;
    }
    if (_lastBaseConfiguration != configuration) {
      _logger.info(
          "Synchronized last base route to: ${configuration.runtimeType}");
      _lastBaseConfiguration = configuration;
    }
  }

  void clearRequest() {
    _routeRequest$.add(null);
  }

  /// Navigates to the last known base route, or to login when there is no
  /// usable navigation history.
  void navigateBackOrLogin() {
    _logger.debug("Request received to navigate back or login.");
    _navigateToLastBaseOr(_delegate.getLoginRoute());
  }

  void dismissModal() {
    _logger.debug("Request received to dismiss modal.");

    _navigateToLastBaseOr(_delegate.getPostLoginDefaultRoute());
  }

  /// One step up. A shown modal: dismissModal(), returns true. Otherwise the
  /// shown base has a parent: navigateTo(parent), returns true. Otherwise
  /// returns false and requests nothing.
  bool navigateUp() {
    if (_modalRoute$.value != null) {
      dismissModal();
      return true;
    }
    final parent = _baseRoute$.value?.parent;
    if (parent == null) return false;
    _logger.debug("Request received to navigate up to: ${parent.runtimeType}");
    navigateTo(parent);
    return true;
  }

  void _navigateToLastBaseOr(ConfigurationBase fallback) {
    // Only navigate back to the previous base if it is known. Transient
    // routes are never kept as the last base.
    if (_lastBaseConfiguration != null) {
      _logger.info(
        "Requesting navigation back to last base route: ${_lastBaseConfiguration!.runtimeType}",
      );
      _processRequest(_lastBaseConfiguration!);
    } else {
      _logger.warning(
        "Cannot navigate back: last base configuration is unknown. Requesting ${fallback.runtimeType} as fallback.",
      );
      _processRequest(fallback);
    }
  }

  void _processRequest(ConfigurationBase configuration) {
    _logger.verbose(
      'Processing request for route: ${configuration.runtimeType}',
    );

    bool isModalRoute = configuration.isModal;
    bool isErrorRoute = configuration is ErrorRoute;
    bool isTransientRoute = _routes.isTransient(configuration);

    if (!isModalRoute && !isErrorRoute && !isTransientRoute) {
      if (_lastBaseConfiguration != configuration) {
        _logger.debug(
          "Updating last base route request to: ${configuration.runtimeType}",
        );
        _lastBaseConfiguration = configuration;
      }
    }
    _logger.info('Emitting route request: ${configuration.runtimeType}');
    _routeRequest$.add(configuration);
  }

  void dispose() {
    _logger.info('Disposing NavigationService.');
    _routeRequest$.close();
    _baseRoute$.close();
    _modalRoute$.close();
  }
}
