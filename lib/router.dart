import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';

import 'app_coordinator.dart';
import 'model/error_models.dart';
import 'route_table.dart';
import 'utils.dart';

// --- Part 1: Route Configuration (Core) ---

/// Defines the contract for all route configurations within the application.
///
/// Each configuration represents a specific destination or state that can be
/// navigated to, and is responsible for generating its corresponding [Uri].
abstract class ConfigurationBase {
  /// A root route (`/`) is replaced by the post-login route when signed in.
  final bool isRoot;

  /// A modal route is shown over the current base page.
  final bool isModal;

  /// Creates a base configuration.
  const ConfigurationBase({this.isRoot = false, this.isModal = false});

  /// The path template this route is bound under, e.g. '/cases/:id'.
  /// Declare it once as `static const path` on the route, return it here,
  /// and give the same constant to the route's binding.
  String get pathTemplate;

  /// Values by name. A name that matches a `:name` segment of
  /// [pathTemplate] fills it; the others become query parameters, in map
  /// order. Default: none.
  Map<String, String> get params => const {};

  /// Built by [buildRouteUri] from [pathTemplate] and [params]. May be overridden.
  Uri get uri => buildRouteUri(pathTemplate, params);

  /// Optional: Defines a default base route to be used if this route is a modal
  /// and is accessed directly (deep-linked) without an existing base context.
  ConfigurationBase? get defaultBaseRoute => null;

  /// Where back goes from this route when no modal is shown, e.g.
  /// SessionNoteRoute(caseId, sessionId).parent => CaseDetailRoute(caseId).
  /// null: a top route; back leaves the app (the platform decides).
  ConfigurationBase? get parent => null;

  /// Same runtimeType and equal [uri].
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConfigurationBase &&
          other.runtimeType == runtimeType &&
          other.uri == uri);

  @override
  int get hashCode => Object.hash(runtimeType, uri);
}

// --- Part 2: Core Routes ---

/// A generic route for handling "404 Not Found" errors.
/// This is a framework-level concept, not tied to application business logic.
class NotFoundRoute extends ConfigurationBase {
  static const String path = '/404';
  /// The URL that matched no route.
  final String originalUrl;

  const NotFoundRoute(this.originalUrl);

  @override
  String get pathTemplate => path;

  /// Also compares [originalUrl], which is not in the URI.
  @override
  bool operator ==(Object other) =>
      super == other &&
      other is NotFoundRoute &&
      other.originalUrl == originalUrl;

  @override
  int get hashCode => Object.hash(super.hashCode, originalUrl);
}

/// A generic route for displaying critical, often unrecoverable, errors.
/// This is a framework-level concept for representing failure states.
class ErrorRoute extends ConfigurationBase {
  static const String path = '/error';
  /// The sentence the error page shows.
  final String message;
  /// Details for logs and custom error pages.
  final HttpProblem? problem;
  /// True when the auth state could not be checked.
  final bool isSessionTermination;

  const ErrorRoute({
    required this.message,
    this.problem,
    this.isSessionTermination = false,
  });

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => {
        'message': message,
        'isSessionTermination': isSessionTermination.toString(),
      };

  /// Also compares [problem], which is not in the URI.
  @override
  bool operator ==(Object other) =>
      super == other && other is ErrorRoute && other.problem == problem;

  @override
  int get hashCode => Object.hash(super.hashCode, problem);
}

// --- Part 3: Route Utilities (Core) ---

/// Fills each `:name` segment with Uri.encodeComponent(params[name]) and puts
/// the remaining params in the query. No remaining params: no '?'.
/// A `:name` with no value in params throws ArgumentError.
Uri buildRouteUri(String pathTemplate, Map<String, String> params) {
  final used = <String>{};
  final filled = pathTemplate.split('/').map((segment) {
    if (!segment.startsWith(':')) return segment;
    final name = segment.substring(1);
    final value = params[name];
    if (value == null) {
      throw ArgumentError.value(
        params,
        'params',
        'No value for ":$name" in "$pathTemplate"',
      );
    }
    used.add(name);
    return Uri.encodeComponent(value);
  }).join('/');
  final rest = {
    for (final entry in params.entries)
      if (!used.contains(entry.key)) entry.key: entry.value,
  };
  return Uri(path: filled, queryParameters: rest.isEmpty ? null : rest);
}

/// Helper function to convert path templates (e.g., '/users/:id') into
/// regular expressions for matching URL paths. Handles named groups for parameters.
RegExp pathToRegExp(String pathTemplate) {
  final pattern = pathTemplate.replaceAllMapped(
    RegExp(r':(\w+)'),
    (match) => '(?<${match.group(1)}>[^/]+)',
  );
  // Make the trailing slash optional.
  final trailingSlashOptionalPattern = pattern.endsWith('/')
      ? '${pattern.substring(0, pattern.length - 1)}/?'
      : '$pattern/?';
  return RegExp('^$trailingSlashOptionalPattern\$');
}

// --- Part 4: Information Parser (Core) ---

/// A generic route information parser that uses a [RouteTable] to convert a
/// URL into a [ConfigurationBase].
class AppRouteInformationParser
    extends RouteInformationParser<ConfigurationBase> {
  final RouteTable routes;

  AppRouteInformationParser(this.routes);

  /// This is triggered by the OS (e.g., deep link, browser back/forth, URL changes).
  /// It parses the URL with the [RouteTable] to create the configuration object.
  @override
  Future<ConfigurationBase> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    return routes.parse(routeInformation.uri);
  }

  /// This is triggered by the [RouterDelegate] to update the browser's URL bar.
  /// It converts a [ConfigurationBase] object back into a [RouteInformation] object.
  @override
  RouteInformation restoreRouteInformation(ConfigurationBase configuration) {
    return RouteInformation(uri: configuration.uri);
  }
}

/// An interface responsible for constructing the Page objects for the router.
///
/// The generic [CoreRouterDelegate] delegates all page creation to an implementation
/// of this class. This allows an application to define its own page types (e.g., with
/// custom transitions) and wrap content in application-specific UI shells.
abstract class RouterPageBuilder {
  /// Builds the primary page for a given base configuration.
  Page buildBasePage(
    BuildContext context,
    ConfigurationBase config,
    Widget contentWidget,
  );

  /// Builds the modal page for a given modal configuration.
  Page buildModalPage(
    BuildContext context,
    ConfigurationBase config,
    Widget contentWidget,
  );
}

/// The main, generic router delegate for the application, driven by [AppCoordinator]'s state.
///
/// It builds the navigator stack based on the application state and delegates the
/// actual construction of `Page` objects to a [RouterPageBuilder]. This keeps the
/// delegate free of any application-specific or platform-specific UI logic.
class CoreRouterDelegate extends RouterDelegate<ConfigurationBase>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<ConfigurationBase> {
  final _logger = useLogger('RoDe', quiet: true);
  @override
  final GlobalKey<NavigatorState> navigatorKey;

  /// The central coordinator managing application state and navigation.
  final AppCoordinator appCoordinator;

  /// The builder responsible for constructing application/platform specific pages.
  final RouterPageBuilder pageBuilder;

  /// Creates the main router delegate.
  CoreRouterDelegate({required this.appCoordinator, required this.pageBuilder})
      : navigatorKey =
            GlobalKey<NavigatorState>(debugLabel: 'CoreDelegateKey') {
    // Listen to the coordinator to rebuild when navigation state changes.
    appCoordinator.addListener(notifyListeners);
  }

  /// Reports the current TOP-MOST route configuration for URL updates.
  @override
  ConfigurationBase? get currentConfiguration {
    if (appCoordinator.currentTopConfiguration is ErrorRoute) {
      return null;
    }
    // This should reflect the URL, which corresponds to the top-most page
    return appCoordinator.currentTopConfiguration;
  }

  /// Handles path changes from the platform (e.g., browser URL changes, deep links).
  /// Delegates the path processing to the [NavigationService] via the [appCoordinator].
  @override
  Future<void> setNewRoutePath(ConfigurationBase configuration) async {
    _logger.verbose(
      '[RouterDelegate] setNewRoutePath called with: ${configuration.runtimeType}',
    );
    appCoordinator.navigationService.routerSetNewPath(configuration);
  }

  /// System back. A modal shown and no leave guards: pops it as the mixin
  /// does, and `onDidRemovePage` dismisses it. Otherwise asks
  /// [NavigationService.navigateBack]; false leaves the app (the platform decides).
  @override
  Future<bool> popRoute() {
    final navigation = appCoordinator.navigationService;
    if (appCoordinator.modalConfiguration != null &&
        !navigation.hasLeaveGuards) {
      return super.popRoute();
    }
    return SynchronousFuture(navigation.navigateBack());
  }

  @override
  Widget build(BuildContext context) {
    _logger.verbose(
      'Building Navigator. Base: ${appCoordinator.baseConfiguration?.runtimeType}, Modal: ${appCoordinator.modalConfiguration?.runtimeType}',
    );
    return Navigator(
      key: navigatorKey,
      pages: _buildPages(context),
      onDidRemovePage: (page) {
        // A modal page removed by system back: dismiss it through the
        // centralized logic. The coordinator state change rebuilds the pages.
        if (page is TransparentModalPage) {
          _logger.debug(
            'Modal page removed. Dismissing via NavigationService.',
          );
          appCoordinator.navigationService.dismissModal();
        }
      },
    );
  }

  /// Builds the list of pages for the root Navigator based on AppCoordinator state.
  List<Page<dynamic>> _buildPages(BuildContext context) {
    final List<Page<dynamic>> pages = [];
    final baseConfig = appCoordinator.baseConfiguration;
    final modalConfig = appCoordinator.modalConfiguration;

    // Get the widget for the base configuration from AppCoordinator. With no
    // base configuration it is the coordinator's own empty frame: the loading
    // scaffold, or the no-state error page.
    final Widget baseWidget = appCoordinator.getBaseContentWidget();

    if (baseConfig != null) {
      // Delegate the entire Page creation to the platform-specific builder.
      pages.add(pageBuilder.buildBasePage(context, baseConfig, baseWidget));
    } else {
      _logger.verbose("No base configuration. Adding the coordinator frame.");
      pages.add(NoAnimationPage(child: baseWidget));
    }

    Widget? modalContentWidget = appCoordinator.getModalContentWidget();

    if (modalConfig != null && modalContentWidget != null) {
      _logger.debug(
        "Adding Modal page to stack for config: ${modalConfig.runtimeType}",
      );
      // Delegate the entire modal Page creation to the application-specific builder.
      pages.add(
        pageBuilder.buildModalPage(context, modalConfig, modalContentWidget),
      );
    }

    _logger.verbose("Built pages stack count: ${pages.length}");
    return pages;
  }

  @override
  @mustCallSuper
  void dispose() {
    appCoordinator.removeListener(notifyListeners);
    super.dispose();
  }
}

class _NoAnimationMaterialPageRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _NoAnimationMaterialPageRoute({
    required MaterialPage<T> page,
    super.allowSnapshotting,
  }) : super(settings: page) {
    assert(opaque);
  }

  MaterialPage<T> get _page => settings as MaterialPage<T>;

  @override
  Widget buildContent(BuildContext context) {
    return _page.child;
  }

  @override
  bool get maintainState => _page.maintainState;

  @override
  bool get fullscreenDialog => _page.fullscreenDialog;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}

/// A MaterialPage that uses our custom [_NoAnimationMaterialPageRoute]
/// to disable all entrance and exit animations for the page itself.
class NoAnimationPage<T> extends MaterialPage<T> {
  const NoAnimationPage({
    required super.child,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
    super.maintainState,
    super.fullscreenDialog,
  });

  @override
  Route<T> createRoute(BuildContext context) {
    return _NoAnimationMaterialPageRoute<T>(
      page: this,
      allowSnapshotting: allowSnapshotting,
    );
  }
}

/// A custom Flutter [Page] that creates a modal-style route ([_TransparentModalRoute]).
///
/// This page is used within the declarative Navigator 2.0 API (`Navigator.pages`)
/// to represent a route that should appear as a modal overlay (e.g., dialog, bottom sheet).
/// It uses [_TransparentModalRoute] internally, which is based on [PopupRoute].
class TransparentModalPage<T> extends Page<T> {
  /// The widget to display as the content of the modal.
  final Widget child;

  /// The color to use for the modal barrier. Defaults to transparent black.
  final Color barrierColor;

  /// Whether tapping the modal barrier dismisses the route. Defaults to true.
  final bool barrierDismissible;

  /// The semantic label for the modal barrier. Read by screen readers.
  final String? barrierLabel;

  /// Creates a page that represents a transparent modal route.
  ///
  /// The [name], [arguments], [key], and [restorationId] are passed to the
  /// underlying [Page] constructor.
  const TransparentModalPage({
    required this.child,
    this.barrierColor = Colors.black54, // Default barrier color
    this.barrierDismissible = false, // Default dismissible behavior
    this.barrierLabel, // Optional barrier label
    super.key, // Pass key to super
    super.name, // Pass name to super
    super.arguments, // Pass arguments to super
    super.restorationId, // Pass restorationId to super
  });

  /// Creates the specialized modal route ([_TransparentModalRoute]).
  @override
  Route<T> createRoute(BuildContext context) {
    return _TransparentModalRoute<T>(
      // Pass the Page itself as settings, which includes name, arguments, etc.
      settings: this,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
    );
  }
}

/// A custom [PopupRoute] used by [TransparentModalPage] to achieve a modal look and feel.
///
/// It renders a modal barrier and defines transitions suitable for modals.
class _TransparentModalRoute<T> extends PopupRoute<T> {
  /// Creates a transparent modal route.
  ///
  /// Requires [settings] (typically the [TransparentModalPage] instance),
  /// and parameters for barrier behavior and appearance.
  _TransparentModalRoute({
    required RouteSettings settings, // Accept settings from the Page
    required this.barrierColor,
    required this.barrierDismissible,
    required this.barrierLabel,
  }) : super(settings: settings); // Pass settings to the PopupRoute constructor

  @override
  final Color barrierColor;

  @override
  final bool barrierDismissible;

  @override
  final String? barrierLabel;

  @override
  // Define the duration for the modal entrance/exit animation.
  Duration get transitionDuration =>
      const Duration(milliseconds: 300); // Example duration

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // The actual content widget is part of the Page settings.
    // Retrieve the child widget from the settings (which is the TransparentModalPage).
    final page = settings as TransparentModalPage<T>;
    // Return the child widget provided by the Page.
    // It might need wrapping for alignment or theming if not handled by the child itself.
    return page.child;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Define how the modal appears and disappears.
    // Example: Fade transition.
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut, // Adjust curve as needed
      ),
      // Apply secondary animation for transitions when another route is pushed on top.
      // Example: Slight fade out for the modal when something covers it.
      // child: FadeTransition(
      //   opacity: CurvedAnimation(
      //     parent: secondaryAnimation,
      //     curve: Curves.easeInOut,
      //     reverseCurve: Curves.easeInOut.flipped
      //   ),
      //   child: child,
      // ),
      child: child, // The widget built by buildPage
    );
  }
}
