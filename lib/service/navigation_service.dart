import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../route_table.dart';
import '../router.dart';
import '../utils.dart';
import '../app_coordinator_delegate.dart';

/// Captures navigation requests (intentions) and emits the requested route configuration.
class NavigationService {
  final _logger = useLogger('NavS');
  final NavigationServiceDelegate _delegate;
  final RouteTable _routes;

  static const String _postAuthRedirectKey = 'post_auth_redirect_intent';
  static const int _redirectIntentLifetimeMinutes = 5;

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
  })  : _delegate = delegate,
        _routes = routes {
    _logger.verbose(
      "NavigationService initialized with ${_routes.bindings.length} routes",
    );
  }

  /// Asynchronously stores the provided [configuration] URI and a timestamp
  /// in SharedPreferences. This is intended to persist a navigation request
  /// across an external authentication redirect.
  Future<void> setPostAuthRedirect(ConfigurationBase configuration) async {
    final prefs = await SharedPreferences.getInstance();
    final intent = {
      'uri': configuration.uri.toString(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(_postAuthRedirectKey, jsonEncode(intent));
    _logger.info('Saved post-auth redirect intent: ${intent['uri']}');
  }

  /// Asynchronously reads, validates, and consumes a stored post-authentication
  /// redirect intent from SharedPreferences.
  ///
  /// This method reads the intent, immediately deletes it to ensure it's
  /// single-use, validates its timestamp, and then parses the URI back into
  /// a `ConfigurationBase` object.
  Future<ConfigurationBase?> consumePostAuthRedirect() async {
    final prefs = await SharedPreferences.getInstance();
    final intentJson = prefs.getString(_postAuthRedirectKey);

    if (intentJson == null) {
      return null;
    }

    // CRITICAL: Immediately delete the key to ensure it is only ever consumed once.
    await prefs.remove(_postAuthRedirectKey);
    _logger.verbose('Consumed and removed post-auth redirect key.');

    try {
      final intent = jsonDecode(intentJson);
      final uriString = intent['uri'] as String?;
      final timestampMillis = intent['timestamp'] as int?;

      if (uriString == null || timestampMillis == null) {
        _logger.warning('Stored redirect intent is malformed.');
        return null;
      }

      final storedTime = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
      final expiryTime = storedTime.add(
        const Duration(minutes: _redirectIntentLifetimeMinutes),
      );

      if (DateTime.now().isAfter(expiryTime)) {
        _logger.warning(
          'Stored redirect intent has expired (stored: $storedTime). Ignoring.',
        );
        return null;
      }

      if (uriString == '/') {
        _logger.info('Attempted to go HomeRoute from Post login flow');
        // Return null if the previous tried is '/', which is home, then we default to nothing.
        return null;
      }

      _logger.info('Found fresh, valid post-auth redirect to: $uriString');
      return _routes.parse(Uri.parse(uriString));
    } catch (e, s) {
      _logger.error('Failed to parse or validate post-auth intent', e, s);
      return null;
    }
  }

  /// Asynchronously clears any stored post-authentication redirect intent.
  /// This should be called on explicit logout to clean up state.
  Future<void> clearPostAuthRedirect() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_postAuthRedirectKey)) {
      await prefs.remove(_postAuthRedirectKey);
      _logger.info('Cleared post-authentication redirect intent on logout.');
    }
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
