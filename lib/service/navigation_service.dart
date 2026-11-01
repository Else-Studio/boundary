import 'package:rxdart/rxdart.dart';

import '../disposable.dart';
import '../route_table.dart';
import '../router.dart';
import '../utils.dart';
import '../app_coordinator_delegate.dart';
import 'leave_guard.dart';
import 'post_auth_redirect_store.dart';
import 'unload_warning.dart';

/// Captures navigation requests (intentions) and emits the requested route configuration.
class NavigationService {
  final _logger = useLogger('NavS');
  final NavigationServiceDelegate _delegate;
  final RouteTable _routes;

  final PostAuthRedirectStore _redirectStore;
  final UnloadWarning _unloadWarning;

  final _routeRequest$ = BehaviorSubject<ConfigurationBase?>();
  final _baseRoute$ = BehaviorSubject<ConfigurationBase?>.seeded(null);
  final _modalRoute$ = BehaviorSubject<ConfigurationBase?>.seeded(null);
  ConfigurationBase? _lastBaseConfiguration;

  /// The base routes shown, oldest first. See [navigateBack].
  final List<ConfigurationBase> _history = [];

  /// Whether the last emitted request is the parent that [navigateBack] asked
  /// for as its fallback. That parent replaces the current history entry.
  bool _lastRequestReplaces = false;

  final List<LeaveGuard> _leaveGuards = [];
  bool _leaveCheckRunning = false;

  /// The routes requested, before access rules and guards. The coordinator
  /// listens to it.
  ValueStream<ConfigurationBase?> get routeRequestStream =>
      _routeRequest$.stream;

  /// The last route requested, or null.
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
    _recordShown(base);
    if (_baseRoute$.value != base) _baseRoute$.add(base);
    if (_modalRoute$.value != modal) _modalRoute$.add(modal);
  }

  NavigationService({
    required NavigationServiceDelegate delegate,
    required RouteTable routes,
    PostAuthRedirectStore? redirectStore,
  })  : _delegate = delegate,
        _routes = routes,
        _redirectStore = redirectStore ?? InMemoryPostAuthRedirectStore(),
        _unloadWarning = createUnloadWarning() {
    _logger.verbose(
      "NavigationService initialized with ${_routes.bindings.length} routes",
    );
    _unloadWarning.attach(() => hasUnsavedChanges);
  }

  /// Runs [guard] before leaving, until the returned [Disposable] is disposed.
  Disposable addLeaveGuard(LeaveGuard guard) {
    _leaveGuards.add(guard);
    return _LeaveGuardRegistration(() => _leaveGuards.remove(guard));
  }

  /// Whether any leave guard is registered.
  bool get hasLeaveGuards => _leaveGuards.isNotEmpty;

  /// Any registered guard has unsaved changes.
  bool get hasUnsavedChanges =>
      _leaveGuards.any((guard) => guard.hasUnsavedChanges);

  /// Requests [route] without asking leave guards. For the coordinator's own
  /// redirects; apps use [navigateTo].
  void redirectTo(ConfigurationBase route) {
    _logger.debug(
      "Redirect request received (unguarded): ${route.runtimeType}",
    );
    _emitRequest(route);
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
      _logger.info('Dropping a stored redirect to $uri');
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

  /// Requests [configuration]. Leave guards run first, unless a modal opens
  /// over a page or the route is already shown.
  void navigateTo(ConfigurationBase configuration) {
    _logger.debug(
      "Request received to navigate to: ${configuration.runtimeType}",
    );
    _requestGuarded(configuration);
  }

  /// For the router: a URL from the platform, such as a deep link. Leave
  /// guards do not run.
  void routerSetNewPath(ConfigurationBase configuration) {
    _logger.debug(
      "Platform requested navigation path: ${configuration.runtimeType}",
    );
    _emitRequest(configuration);
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

  /// Navigates to the last known base route, or to login when there is no
  /// usable navigation history.
  void navigateBackOrLogin() {
    _logger.debug("Request received to navigate back or login.");
    _navigateToLastBaseOr(_delegate.getLoginRoute());
  }

  /// Closes the modal: requests the last base route, or the post-login route
  /// when there is none. Leave guards run first.
  void dismissModal() {
    _logger.debug("Request received to dismiss modal.");

    _navigateToLastBaseOr(_delegate.getPostLoginDefaultRoute());
  }

  /// One step up. A shown modal: dismissModal(), returns true. Otherwise the
  /// shown base has a parent: navigateTo(parent), returns true. Otherwise
  /// returns false and requests nothing.
  ///
  /// The bool is synchronous: true when there was a modal or a parent, even
  /// when a leave guard later vetoes the request.
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

  /// Dismisses a shown modal; else shows the previous base route and drops the
  /// current one; else does what [navigateUp] does. True when it requested anything.
  bool navigateBack() {
    if (_modalRoute$.value != null) {
      dismissModal();
      return true;
    }
    final shown = _baseRoute$.value;
    final previous = _history.isNotEmpty && shown == _history.last
        ? (_history.length >= 2 ? _history[_history.length - 2] : null)
        : _history.lastOrNull;
    if (previous != null) {
      _logger.debug(
        "Request received to navigate back to: ${previous.runtimeType}",
      );
      _requestGuarded(previous);
      return true;
    }
    final parent = shown?.parent;
    if (parent == null) return false;
    _logger.debug(
      "No previous route. Navigating back to the parent: ${parent.runtimeType}",
    );
    _requestGuarded(parent, replace: true);
    return true;
  }

  /// Updates the history for the shown base route [base].
  void _recordShown(ConfigurationBase? base) {
    if (base == null || _routes.isTransient(base)) return;
    if (base == _delegate.getLoginRoute()) {
      _history
        ..clear()
        ..add(base);
      return;
    }
    if (_history.isNotEmpty && _history.last == base) return;
    if (_history.length >= 2 && _history[_history.length - 2] == base) {
      _history.removeLast();
      return;
    }
    final request = _routeRequest$.valueOrNull;
    final replacesLast = request != null &&
        !request.isModal &&
        request is! ErrorRoute &&
        !_routes.isTransient(request) &&
        (request != base || _lastRequestReplaces);
    if (replacesLast && _history.isNotEmpty) {
      _history[_history.length - 1] = base;
    } else {
      _history.add(base);
    }
  }

  void _navigateToLastBaseOr(ConfigurationBase fallback) {
    // Only navigate back to the previous base if it is known. Transient
    // routes are never kept as the last base.
    if (_lastBaseConfiguration != null) {
      _logger.info(
        "Requesting navigation back to last base route: ${_lastBaseConfiguration!.runtimeType}",
      );
      _requestGuarded(_lastBaseConfiguration!);
    } else {
      _logger.warning(
        "Cannot navigate back: last base configuration is unknown. Requesting ${fallback.runtimeType} as fallback.",
      );
      _requestGuarded(fallback);
    }
  }

  void _requestGuarded(ConfigurationBase target, {bool replace = false}) {
    if (_leaveCheckRunning) {
      _logger.debug(
        'Dropping navigation request while a leave check is running: ${target.runtimeType}',
      );
      return;
    }

    final shown = _modalRoute$.value ?? _baseRoute$.value;
    final openingModalOverPage =
        target.isModal && _modalRoute$.value == null;
    if (_leaveGuards.isEmpty || target == shown || openingModalOverPage) {
      _emitRequest(target, replace: replace);
      return;
    }

    _leaveCheckRunning = true;
    _runLeaveGuardsThen(target, replace: replace);
  }

  Future<void> _runLeaveGuardsThen(
    ConfigurationBase target, {
    required bool replace,
  }) async {
    try {
      for (final guard in List<LeaveGuard>.of(_leaveGuards)) {
        try {
          final allowed = await guard.mayLeave();
          if (!allowed) {
            _logger.debug(
              'Leave guard vetoed navigation to ${target.runtimeType}',
            );
            return;
          }
        } catch (error, stackTrace) {
          _logger.error(
            'Leave guard failed for ${target.runtimeType}',
            error,
            stackTrace,
          );
          return;
        }
      }
      _emitRequest(target, replace: replace);
    } finally {
      _leaveCheckRunning = false;
    }
  }

  void _emitRequest(ConfigurationBase configuration, {bool replace = false}) {
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
    _lastRequestReplaces = replace;
    _routeRequest$.add(configuration);
  }

  void dispose() {
    _logger.info('Disposing NavigationService.');
    _unloadWarning.dispose();
    _history.clear();
    _routeRequest$.close();
    _baseRoute$.close();
    _modalRoute$.close();
  }
}

class _LeaveGuardRegistration implements Disposable {
  _LeaveGuardRegistration(this._remove);

  final void Function() _remove;
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _remove();
  }
}
