import 'dart:async';

import 'package:auto_injector/auto_injector.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'controller.dart';
import 'default_pages.dart';
import 'router.dart';

/// Who may see a destination.
enum RouteAccess { public, guestOnly, protected }

/// The answer of a [RouteGuard]: [GuardResult.allow] or
/// [GuardResult.redirect].
sealed class GuardResult {
  const GuardResult._();

  const factory GuardResult.allow() = GuardAllow;
  const factory GuardResult.redirect(ConfigurationBase route) = GuardRedirect;
}

final class GuardAllow extends GuardResult {
  const GuardAllow() : super._();
}

final class GuardRedirect extends GuardResult {
  const GuardRedirect(this.route) : super._();

  final ConfigurationBase route;
}

/// App policy (roles, data policy, ...). Gets its services from its own
/// constructor; it is not given the auth state.
abstract interface class RouteGuard {
  FutureOr<GuardResult> check(ConfigurationBase route);
}

/// One destination: its path template, how to parse its route from a URL, and
/// how to build its controller and page.
class RouteBinding<R extends ConfigurationBase, C extends Controller> {
  const RouteBinding({
    required this.path,
    required this.parse,
    required this.controller,
    required this.page,
    this.access = RouteAccess.protected,
    this.transient = false,
  });

  /// R's `static const path`, e.g. `CaseRoute.path`.
  final String path;

  /// Path params (decoded) and query params, by name.
  final R Function(Map<String, String> params) parse;

  /// Creates the controller for this destination.
  final C Function(AutoInjector injector) controller;

  /// The view, which reads its controller from Provider.
  final Widget page;

  final RouteAccess access;

  /// Never kept as the "last base" in NavigationService.
  final bool transient;

  Type get routeType => R;

  /// Creates the controller with [controller], then calls enter(route) on it.
  Controller createController(AutoInjector injector, ConfigurationBase route) {
    final created = controller(injector);
    created.enter(route as R);
    return created;
  }

  /// `Provider<C>.value(value: controller as C, child: page)`.
  Widget buildView(Controller controller) {
    return Provider<C>.value(value: controller as C, child: page);
  }
}

/// The bindings of an app, and the parsing of URLs into routes.
class RouteTable {
  /// Throws ArgumentError when two bindings have the same route type.
  /// Appends defaultErrorRouteBinding and defaultNotFoundRouteBinding, in that
  /// order, for each of the two route types the list does not bind.
  RouteTable(List<RouteBinding> bindings)
      : _bindings = List.unmodifiable([
          ...bindings,
          if (!bindings.any((b) => b.routeType == ErrorRoute))
            defaultErrorRouteBinding,
          if (!bindings.any((b) => b.routeType == NotFoundRoute))
            defaultNotFoundRouteBinding,
        ]) {
    for (final binding in _bindings) {
      if (_byType.containsKey(binding.routeType)) {
        throw ArgumentError.value(
          bindings,
          'bindings',
          'Two bindings for route type ${binding.routeType}',
        );
      }
      _byType[binding.routeType] = binding;
      _patterns.add(pathToRegExp(binding.path));
    }
  }

  final List<RouteBinding> _bindings;
  final Map<Type, RouteBinding> _byType = {};
  final List<RegExp> _patterns = [];

  /// The bindings, unmodifiable: the given ones in order, then the defaults.
  List<RouteBinding> get bindings => _bindings;

  /// The first binding (in order) whose path matches uri.path parses it.
  /// Path params are Uri-decoded and win over a query param of the same name.
  /// That binding's parse throwing gives NotFoundRoute(uri.toString()), and
  /// no later binding is tried. No match gives NotFoundRoute(uri.toString()).
  ConfigurationBase parse(Uri uri) {
    for (var i = 0; i < _bindings.length; i++) {
      final match = _patterns[i].firstMatch(uri.path);
      if (match == null) continue;
      try {
        final params = <String, String>{
          ...uri.queryParameters,
          for (final name in match.groupNames)
            name: Uri.decodeComponent(match.namedGroup(name)!),
        };
        return _bindings[i].parse(params);
      } catch (_) {
        return NotFoundRoute(uri.toString());
      }
    }
    return NotFoundRoute(uri.toString());
  }

  /// The binding's transient flag; false for a route type with no binding.
  bool isTransient(ConfigurationBase route) {
    return _byType[route.runtimeType]?.transient ?? false;
  }

  /// The binding whose route type is route.runtimeType. Throws StateError
  /// naming the type when there is none, and when route.pathTemplate is not
  /// the binding's path (the binding was given another route's constant).
  RouteBinding bindingFor(ConfigurationBase route) {
    final binding = _byType[route.runtimeType];
    if (binding == null) {
      throw StateError('No binding for route type ${route.runtimeType}');
    }
    if (binding.path != route.pathTemplate) {
      throw StateError(
        'Binding for ${route.runtimeType} has path "${binding.path}", '
        'but the route is at "${route.pathTemplate}"',
      );
    }
    return binding;
  }
}
