import 'package:auto_injector/auto_injector.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'router.dart';

/// One destination: its path template, how to parse its route from a URL, and
/// how to build its controller and page.
class RouteBinding<R extends ConfigurationBase, C extends Controller> {
  const RouteBinding({
    required this.path,
    required this.parse,
    required this.controller,
    required this.page,
  });

  /// R's `static const path`, e.g. `CaseRoute.path`.
  final String path;

  /// Path params (decoded) and query params, by name.
  final R Function(Map<String, String> params) parse;

  /// Used from the coordinator slice.
  final C Function(AutoInjector injector) controller;

  /// Used from the coordinator slice: the view, which reads its controller
  /// from Provider.
  final Widget page;

  Type get routeType => R;
}

/// The bindings of an app, and the parsing of URLs into routes.
class RouteTable {
  // Stub: the real constructor throws ArgumentError on two bindings with the
  // same route type, and precompiles one RegExp per binding.
  RouteTable(List<RouteBinding> bindings) : _bindings = bindings;

  final List<RouteBinding> _bindings;

  /// The bindings, unmodifiable, in the order given.
  List<RouteBinding> get bindings => _bindings;

  /// The first binding (in order) whose path matches uri.path parses it.
  ConfigurationBase parse(Uri uri) {
    throw UnimplementedError('not implemented');
  }

  /// The binding whose route type is route.runtimeType.
  RouteBinding bindingFor(ConfigurationBase route) {
    throw UnimplementedError('not implemented');
  }
}
