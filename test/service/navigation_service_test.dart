import 'dart:convert';

import 'package:boundary/boundary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestRoute extends ConfigurationBase {
  final String path;

  const _TestRoute(this.path);

  @override
  String get pathTemplate => path;
}

class _TestCallbackRoute extends _TestRoute {
  const _TestCallbackRoute() : super('/callback');
}

class _CaseRoute extends ConfigurationBase {
  static const String path = '/cases/:id';

  const _CaseRoute(this.id);

  final int id;

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => {'id': '$id'};
}

class _NoopController extends Controller<void> {
  @override
  void handleAction(void action) {}
}

RouteBinding<R, _NoopController> _bind<R extends ConfigurationBase>(
  String path,
  R Function(Map<String, String>) parse,
) =>
    RouteBinding<R, _NoopController>(
      path: path,
      parse: parse,
      controller: (_) => _NoopController(),
      page: const SizedBox(),
    );

class _NoteModalRoute extends ConfigurationBase {
  static const String path = '/notes/:id';

  const _NoteModalRoute(this.id) : super(isModal: true);

  final int id;

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => {'id': '$id'};
}

final _caseBinding = _bind<_CaseRoute>(
  _CaseRoute.path,
  (p) => _CaseRoute(int.parse(p['id']!)),
);

RouteTable _routes() => RouteTable([
      _bind<_TestRoute>('/base', (_) => const _TestRoute('/base')),
      _bind<_TestCallbackRoute>(
          '/callback', (_) => const _TestCallbackRoute()),
    ]);

class _TestDelegate implements NavigationServiceDelegate {
  final ConfigurationBase loginRoute;

  const _TestDelegate(this.loginRoute);

  @override
  ConfigurationBase getLoginRoute() => loginRoute;

  @override
  bool isAuthCallbackRoute(ConfigurationBase config) =>
      config is _TestCallbackRoute;

  @override
  ConfigurationBase getPostLoginDefaultRoute() => const _TestRoute('/home');
}

void main() {
  test('navigateBackOrLogin uses history and falls back to login', () {
    const login = _TestRoute('/login');
    const base = _TestRoute('/base');

    final service = NavigationService(
      delegate: const _TestDelegate(login),
      routes: _routes(),
    );
    service.navigateTo(base);
    service.navigateBackOrLogin();
    expect(service.currentRequestedConfiguration, same(base));
    service.dispose();

    final fallbackService = NavigationService(
      delegate: const _TestDelegate(login),
      routes: _routes(),
    );
    fallbackService.navigateBackOrLogin();
    expect(fallbackService.currentRequestedConfiguration, same(login));
    fallbackService.dispose();
  });
  test('does not retain auth callback as navigation history', () {
    const login = _TestRoute('/login');
    const base = _TestRoute('/base');
    const callback = _TestCallbackRoute();

    final service = NavigationService(
      delegate: const _TestDelegate(login),
      routes: _routes(),
    );
    service.navigateTo(base);
    service.navigateTo(callback);
    service.navigateBackOrLogin();

    expect(service.currentRequestedConfiguration, same(base));
    service.dispose();

    final callbackOnlyService = NavigationService(
      delegate: const _TestDelegate(login),
      routes: _routes(),
    );
    callbackOnlyService.syncBaseConfiguration(callback);
    callbackOnlyService.navigateBackOrLogin();
    expect(callbackOnlyService.currentRequestedConfiguration, same(login));
    callbackOnlyService.dispose();
  });

  group('stored post-auth redirect', () {
    Future<ConfigurationBase?> consumeStored(String uri) async {
      SharedPreferences.setMockInitialValues({
        'post_auth_redirect_intent': jsonEncode({
          'uri': uri,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      });
      final service = NavigationService(
        delegate: const _TestDelegate(_TestRoute('/login')),
        routes: RouteTable([_caseBinding]),
      );
      try {
        return await service.consumePostAuthRedirect();
      } finally {
        service.dispose();
      }
    }

    test('a stored redirect is parsed with the route table', () async {
      final route = await consumeStored('/cases/7');

      expect(route, const _CaseRoute(7));
    });

    test('a stored redirect the table cannot parse gives a not-found route',
        () async {
      final route = await consumeStored('/cases/abc');

      expect(route, const NotFoundRoute('/cases/abc'));
    });
  });

  group('resolved routes', () {
    late NavigationService service;

    setUp(() {
      service = NavigationService(
        delegate: const _TestDelegate(_TestRoute('/login')),
        routes: _routes(),
      );
    });

    tearDown(() => service.dispose());

    test('streams what it is told, once per change', () async {
      final bases = <ConfigurationBase?>[];
      final modals = <ConfigurationBase?>[];
      service.baseRouteStream.listen(bases.add);
      service.modalRouteStream.listen(modals.add);

      service.onRouteResolved(base: const _CaseRoute(7), modal: null);
      service.onRouteResolved(
          base: const _CaseRoute(7), modal: const _NoteModalRoute(1));
      service.onRouteResolved(base: const _CaseRoute(7), modal: null);
      await Future<void>.delayed(Duration.zero);

      expect(bases, [null, const _CaseRoute(7)]);
      expect(modals, [null, const _NoteModalRoute(1), null]);
    });

    test('dispose closes both streams', () async {
      service.dispose();

      await expectLater(
        service.baseRouteStream,
        emitsInOrder([anything, emitsDone]),
      );
      await expectLater(
        service.modalRouteStream,
        emitsInOrder([anything, emitsDone]),
      );
    });
  });
}
