import 'dart:async';

import 'package:boundary/boundary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestGuard implements LeaveGuard {
  TestGuard({Completer<bool>? answer, bool? fixed, this.unsaved = false})
      : _answer = answer,
        _fixed = fixed;

  final Completer<bool>? _answer;
  final bool? _fixed;
  final bool unsaved;
  int mayLeaveCalls = 0;

  @override
  bool get hasUnsavedChanges => unsaved;

  @override
  Future<bool> mayLeave() {
    mayLeaveCalls++;
    if (_fixed != null) return Future<bool>.value(_fixed);
    return _answer!.future;
  }
}

class _ThrowingGuard implements LeaveGuard {
  @override
  bool get hasUnsavedChanges => false;

  @override
  Future<bool> mayLeave() => throw StateError('x');
}

class _RouteA extends ConfigurationBase {
  static const String path = '/a';

  const _RouteA();

  @override
  String get pathTemplate => path;
}

class _RouteB extends ConfigurationBase {
  static const String path = '/b';

  const _RouteB();

  @override
  String get pathTemplate => path;
}

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

  @override
  ConfigurationBase? get parent => const _RouteA();
}

class _NoopController extends Controller<void> {
  @override
  void handleAction(void action) {}
}

RouteBinding<R, _NoopController> _bind<R extends ConfigurationBase>(
  String path,
  R Function(Map<String, String>) parse, {
  RouteAccess access = RouteAccess.protected,
  bool transient = false,
}) =>
    RouteBinding<R, _NoopController>(
      path: path,
      parse: parse,
      controller: (_) => _NoopController(),
      page: const SizedBox(),
      access: access,
      transient: transient,
    );

class _AboutRoute extends ConfigurationBase {
  static const String path = '/about';

  const _AboutRoute();

  @override
  String get pathTemplate => path;
}

class _GuestRoute extends ConfigurationBase {
  static const String path = '/login';

  const _GuestRoute();

  @override
  String get pathTemplate => path;
}

class _UnboundRoute extends ConfigurationBase {
  const _UnboundRoute();

  @override
  String get pathTemplate => '/unbound';
}

class _NoteModalRoute extends ConfigurationBase {
  static const String path = '/notes/:id';

  const _NoteModalRoute(this.id) : super(isModal: true);

  final int id;

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => {'id': '$id'};
}

class _CasesRoute extends ConfigurationBase {
  static const String path = '/cases';

  const _CasesRoute();

  @override
  String get pathTemplate => path;
}

class _CaseDetailRoute extends ConfigurationBase {
  static const String path = '/cases/:id';

  const _CaseDetailRoute(this.id);

  final String id;

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => {'id': id};

  @override
  ConfigurationBase? get parent => const _CasesRoute();
}

class _SessionNoteRoute extends ConfigurationBase {
  static const String path = '/cases/:caseId/sessions/:sessionId';

  const _SessionNoteRoute(this.caseId, this.sessionId);

  final String caseId;
  final String sessionId;

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => {'caseId': caseId, 'sessionId': sessionId};

  @override
  ConfigurationBase? get parent => _CaseDetailRoute(caseId);
}

class _CaseNoteModalRoute extends ConfigurationBase {
  static const String path = '/note';

  const _CaseNoteModalRoute() : super(isModal: true);

  @override
  String get pathTemplate => path;
}

final _caseBinding = _bind<_CaseRoute>(
  _CaseRoute.path,
  (p) => _CaseRoute(int.parse(p['id']!)),
);

RouteTable _routes() => RouteTable([
      _bind<_TestRoute>('/base', (_) => const _TestRoute('/base')),
      _bind<_TestCallbackRoute>(
        '/callback',
        (_) => const _TestCallbackRoute(),
        access: RouteAccess.public,
        transient: true,
      ),
    ]);

class _TestDelegate implements NavigationServiceDelegate {
  final ConfigurationBase loginRoute;

  const _TestDelegate(this.loginRoute);

  @override
  ConfigurationBase getLoginRoute() => loginRoute;

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
  test('a transient route is not kept as navigation history', () {
    const guest = _GuestRoute();
    const about = _AboutRoute();
    const callback = _TestCallbackRoute();
    RouteTable table() => RouteTable([
          _bind<_AboutRoute>(_AboutRoute.path, (_) => about,
              access: RouteAccess.public),
          _bind<_TestCallbackRoute>('/callback', (_) => callback,
              access: RouteAccess.public, transient: true),
          _bind<_GuestRoute>(_GuestRoute.path, (_) => guest,
              access: RouteAccess.guestOnly),
        ]);

    final service = NavigationService(
      delegate: const _TestDelegate(guest),
      routes: table(),
    );
    service.navigateTo(about);
    service.navigateTo(callback);
    service.navigateBackOrLogin();

    expect(service.currentRequestedConfiguration, same(about));
    service.dispose();

    final callbackOnlyService = NavigationService(
      delegate: const _TestDelegate(guest),
      routes: table(),
    );
    callbackOnlyService.syncBaseConfiguration(callback);
    callbackOnlyService.navigateBackOrLogin();
    expect(callbackOnlyService.currentRequestedConfiguration, same(guest));
    callbackOnlyService.dispose();
  });

  test('a route with no binding is not transient and does not throw', () {
    const unbound = _UnboundRoute();
    const callback = _TestCallbackRoute();

    final service = NavigationService(
      delegate: const _TestDelegate(_GuestRoute()),
      routes: RouteTable([
        _bind<_TestCallbackRoute>('/callback', (_) => callback,
            access: RouteAccess.public, transient: true),
      ]),
    );
    service.navigateTo(unbound);
    service.navigateTo(callback);
    service.navigateBackOrLogin();

    expect(service.currentRequestedConfiguration, same(unbound));
    service.dispose();
  });

  group('stored post-auth redirect', () {
    Future<ConfigurationBase?> consumeStored(String uri) async {
      final store = InMemoryPostAuthRedirectStore();
      await store.save(Uri.parse(uri));
      final service = NavigationService(
        delegate: const _TestDelegate(_TestRoute('/login')),
        routes: RouteTable([_caseBinding]),
        redirectStore: store,
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

    test('a stored root redirect gives no route', () async {
      expect(await consumeStored('/'), isNull);
    });

    test('the default redirect is kept in memory and taken once', () async {
      SharedPreferences.setMockInitialValues({});
      final service = NavigationService(
        delegate: const _TestDelegate(_TestRoute('/login')),
        routes: RouteTable([_caseBinding]),
      );

      await service.setPostAuthRedirect(const _CaseRoute(7));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);

      expect(await service.consumePostAuthRedirect(), const _CaseRoute(7));
      expect(await service.consumePostAuthRedirect(), isNull);
      expect(prefs.getKeys(), isEmpty);
      service.dispose();
    });

    test('clearing forgets the redirect', () async {
      final store = InMemoryPostAuthRedirectStore();
      final service = NavigationService(
        delegate: const _TestDelegate(_TestRoute('/login')),
        routes: RouteTable([_caseBinding]),
        redirectStore: store,
      );

      await service.setPostAuthRedirect(const _CaseRoute(7));
      await service.clearPostAuthRedirect();

      expect(await store.take(), isNull);

      expect(await service.consumePostAuthRedirect(), isNull);
      service.dispose();
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

  group('navigateUp', () {
    late NavigationService service;

    setUp(() {
      service = NavigationService(
        delegate: const _TestDelegate(_TestRoute('/login')),
        routes: _routes(),
      );
    });

    tearDown(() => service.dispose());

    test('goes to the parent of the shown base route, step by step', () {
      service.onRouteResolved(
          base: const _SessionNoteRoute('c1', 's1'), modal: null);

      expect(service.navigateUp(), isTrue);
      expect(
          service.currentRequestedConfiguration, const _CaseDetailRoute('c1'));

      service.onRouteResolved(base: const _CaseDetailRoute('c1'), modal: null);

      expect(service.navigateUp(), isTrue);
      expect(service.currentRequestedConfiguration, const _CasesRoute());
    });

    test('at a route with no parent does nothing', () {
      service.navigateTo(const _CasesRoute());
      service.onRouteResolved(base: const _CasesRoute(), modal: null);

      expect(service.navigateUp(), isFalse);
      expect(service.currentRequestedConfiguration, const _CasesRoute());
    });

    test('with nothing shown does nothing', () {
      expect(service.navigateUp(), isFalse);
      expect(service.currentRequestedConfiguration, isNull);
    });

    test('closes a shown modal first, back to the last base route', () {
      service.navigateTo(const _CaseDetailRoute('c1'));
      service.navigateTo(const _CaseNoteModalRoute());
      service.onRouteResolved(
          base: const _CaseDetailRoute('c1'),
          modal: const _CaseNoteModalRoute());

      expect(service.navigateUp(), isTrue);
      expect(
          service.currentRequestedConfiguration, const _CaseDetailRoute('c1'));
    });

    test('uses the shown route, not the requested one, after a redirect', () {
      service.navigateTo(const _SessionNoteRoute('c1', 's1'));
      service.onRouteResolved(base: const _CaseDetailRoute('c1'), modal: null);

      expect(service.navigateUp(), isTrue);
      expect(service.currentRequestedConfiguration, const _CasesRoute());
    });
  });

  group('leave guards', () {
    late NavigationService service;

    RouteTable leaveRoutes() => RouteTable([
          _bind<_RouteA>(_RouteA.path, (_) => const _RouteA(),
              access: RouteAccess.public),
          _bind<_RouteB>(_RouteB.path, (_) => const _RouteB(),
              access: RouteAccess.public),
          _caseBinding,
          _bind<_NoteModalRoute>(
            _NoteModalRoute.path,
            (p) => _NoteModalRoute(int.parse(p['id']!)),
            access: RouteAccess.public,
          ),
        ]);

    setUp(() {
      service = NavigationService(
        delegate: const _TestDelegate(_TestRoute('/login')),
        routes: leaveRoutes(),
      );
    });

    tearDown(() => service.dispose());

    Future<void> showBase(ConfigurationBase route) async {
      service.navigateTo(route);
      service.onRouteResolved(base: route, modal: null);
    }

    test('without guards navigation is immediate', () async {
      await showBase(const _RouteA());

      service.navigateTo(const _RouteB());

      expect(service.currentRequestedConfiguration, const _RouteB());
    });

    test('an allowing guard lets the request through after it answers',
        () async {
      await showBase(const _RouteA());
      final answer = Completer<bool>();
      final guard = TestGuard(answer: answer);
      service.addLeaveGuard(guard);

      service.navigateTo(const _RouteB());

      expect(guard.mayLeaveCalls, 1);
      expect(service.currentRequestedConfiguration, const _RouteA());

      answer.complete(true);
      await pumpEventQueue();

      expect(service.currentRequestedConfiguration, const _RouteB());
    });

    test('a vetoing guard keeps the page', () async {
      await showBase(const _RouteA());
      final emitted = <ConfigurationBase?>[];
      service.routeRequestStream.listen(emitted.add);
      await pumpEventQueue();
      emitted.clear();

      final answer = Completer<bool>();
      service.addLeaveGuard(TestGuard(answer: answer));

      service.navigateTo(const _RouteB());
      answer.complete(false);
      await pumpEventQueue();

      expect(service.currentRequestedConfiguration, const _RouteA());
      expect(emitted, isEmpty);
    });

    test('guards run in order and the first veto stops the rest', () async {
      await showBase(const _RouteA());
      final g1 = TestGuard(fixed: false);
      final g2 = TestGuard(fixed: true);
      service.addLeaveGuard(g1);
      service.addLeaveGuard(g2);

      service.navigateTo(const _RouteB());
      await pumpEventQueue();

      expect(g1.mayLeaveCalls, 1);
      expect(g2.mayLeaveCalls, 0);
      expect(service.currentRequestedConfiguration, const _RouteA());
    });

    test('a disposed registration no longer guards', () async {
      await showBase(const _RouteA());
      final guard = TestGuard(fixed: false);
      final reg = service.addLeaveGuard(guard);
      reg.dispose();

      service.navigateTo(const _RouteB());

      expect(service.currentRequestedConfiguration, const _RouteB());
      expect(guard.mayLeaveCalls, 0);
      expect(service.hasLeaveGuards, isFalse);
    });

    test('opening a modal asks no guard and closing it does', () async {
      await showBase(const _RouteA());
      final answer = Completer<bool>();
      final guard = TestGuard(answer: answer);
      service.addLeaveGuard(guard);

      service.navigateTo(const _NoteModalRoute(1));

      expect(guard.mayLeaveCalls, 0);
      expect(service.currentRequestedConfiguration, const _NoteModalRoute(1));

      service.onRouteResolved(
        base: const _RouteA(),
        modal: const _NoteModalRoute(1),
      );

      service.dismissModal();
      expect(guard.mayLeaveCalls, 1);
      expect(service.currentRequestedConfiguration, const _NoteModalRoute(1));

      answer.complete(true);
      await pumpEventQueue();

      expect(service.currentRequestedConfiguration, const _RouteA());
    });

    test('navigating to the shown route asks no guard', () async {
      await showBase(const _RouteA());
      final guard = TestGuard(fixed: false);
      service.addLeaveGuard(guard);

      service.navigateTo(const _RouteA());

      expect(guard.mayLeaveCalls, 0);
      expect(service.currentRequestedConfiguration, const _RouteA());
    });

    test('going up returns at once and asks the guard', () async {
      service.navigateTo(const _CaseRoute(7));
      service.onRouteResolved(base: const _CaseRoute(7), modal: null);
      final answer = Completer<bool>();
      final guard = TestGuard(answer: answer);
      service.addLeaveGuard(guard);

      expect(service.navigateUp(), isTrue);
      expect(guard.mayLeaveCalls, 1);
      expect(service.currentRequestedConfiguration, const _CaseRoute(7));

      answer.complete(true);
      await pumpEventQueue();

      expect(service.currentRequestedConfiguration, const _RouteA());
    });

    test('going up keeps the page when the guard vetoes', () async {
      service.navigateTo(const _CaseRoute(7));
      service.onRouteResolved(base: const _CaseRoute(7), modal: null);
      final answer = Completer<bool>();
      service.addLeaveGuard(TestGuard(answer: answer));

      expect(service.navigateUp(), isTrue);
      answer.complete(false);
      await pumpEventQueue();

      expect(service.currentRequestedConfiguration, const _CaseRoute(7));
    });

    test('navigateBackOrLogin asks the guard before leaving', () async {
      // Last base is /a while the coordinator is showing /cases/7, so the
      // target is not the shown route and the guard must run.
      service.navigateTo(const _RouteA());
      service.onRouteResolved(base: const _CaseRoute(7), modal: null);
      final answer = Completer<bool>();
      final guard = TestGuard(answer: answer);
      service.addLeaveGuard(guard);

      service.navigateBackOrLogin();

      expect(guard.mayLeaveCalls, 1);
      expect(service.currentRequestedConfiguration, const _CaseRoute(7));

      answer.complete(true);
      await pumpEventQueue();

      expect(service.currentRequestedConfiguration, const _RouteA());
    });

    test('requests during a check are dropped', () async {
      await showBase(const _RouteA());
      final answer = Completer<bool>();
      final guard = TestGuard(answer: answer);
      service.addLeaveGuard(guard);

      service.navigateTo(const _RouteB());
      service.navigateTo(const _CaseRoute(7));

      expect(guard.mayLeaveCalls, 1);

      answer.complete(true);
      await pumpEventQueue();

      expect(service.currentRequestedConfiguration, const _RouteB());
    });

    test('a throwing guard vetoes without throwing to the caller', () async {
      final saved = boundaryLogLevel;
      boundaryLogLevel = LogLevel.critical;
      addTearDown(() => boundaryLogLevel = saved);

      await showBase(const _RouteA());
      service.addLeaveGuard(_ThrowingGuard());

      expect(() => service.navigateTo(const _RouteB()), returnsNormally);
      await pumpEventQueue();

      expect(service.currentRequestedConfiguration, const _RouteA());
    });

    test('redirectTo skips guards', () async {
      await showBase(const _RouteA());
      final guard = TestGuard(fixed: false);
      service.addLeaveGuard(guard);

      service.redirectTo(const _RouteB());

      expect(service.currentRequestedConfiguration, const _RouteB());
      expect(guard.mayLeaveCalls, 0);
    });

    test('unsaved changes are the guards union', () async {
      await showBase(const _RouteA());
      service.addLeaveGuard(TestGuard(fixed: true, unsaved: false));
      final second = service.addLeaveGuard(TestGuard(fixed: true, unsaved: true));

      expect(service.hasUnsavedChanges, isTrue);

      second.dispose();

      expect(service.hasUnsavedChanges, isFalse);
    });
  });
}
