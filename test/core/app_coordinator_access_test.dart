// Test Plan:
//
// group: 'AppCoordinator access'
//   - one test per row of the access table (signed in, no session, session
//     expired, logged out, loading) for public, guest-only and protected routes
//   - the root goes to the default route when signed in
//
// group: 'AppCoordinator guards'
//   - guards run in order and the first redirect wins
//   - a guard redirect goes through the access step again
//   - guards see the post-auth redirect target
//   - a redirect loop ends on an error page
//   - a guard that throws gives an error page
//   - guards are created once

import 'dart:async';

import 'package:boundary/boundary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/mock_dependency_provider.dart';
import '../helpers/mocks.mocks.dart';
import '../helpers/model_factory.dart';
import '../helpers/sut_factory.dart';

class PublicRoute extends ConfigurationBase {
  static const String path = '/about';

  const PublicRoute();

  @override
  String get pathTemplate => path;
}

class GuestRoute extends ConfigurationBase {
  static const String path = '/login';

  const GuestRoute();

  @override
  String get pathTemplate => path;
}

class CasesRoute extends ConfigurationBase {
  static const String path = '/cases';

  const CasesRoute();

  @override
  String get pathTemplate => path;
}

class HomeRoute extends ConfigurationBase {
  static const String path = '/home';

  const HomeRoute();

  @override
  String get pathTemplate => path;
}

class CallbackRoute extends ConfigurationBase {
  static const String path = '/callback';

  const CallbackRoute();

  @override
  String get pathTemplate => path;
}

class RootRoute extends ConfigurationBase {
  static const String path = '/';

  const RootRoute() : super(isRoot: true);

  @override
  String get pathTemplate => path;
}

class NoopController extends Controller<void> {
  @override
  void handleAction(void action) {}
}

/// Records every route it is given and answers with [respond].
class RecordingGuard implements RouteGuard {
  RecordingGuard([this.respond = _allow]);

  FutureOr<GuardResult> Function(ConfigurationBase route) respond;
  final List<ConfigurationBase> seen = [];

  static GuardResult _allow(ConfigurationBase route) =>
      const GuardResult.allow();

  @override
  FutureOr<GuardResult> check(ConfigurationBase route) {
    seen.add(route);
    return respond(route);
  }
}

RouteBinding<R, NoopController> bind<R extends ConfigurationBase>(
  String path,
  R route, {
  RouteAccess access = RouteAccess.protected,
  bool transient = false,
}) =>
    RouteBinding<R, NoopController>(
      path: path,
      parse: (_) => route,
      controller: (_) => NoopController(),
      page: const SizedBox(),
      access: access,
      transient: transient,
    );

Matcher errorRouteWith(String message) =>
    isA<ErrorRoute>().having((r) => r.message, 'message', message);

void main() {
  group('AppCoordinator access', () {
    late MockDependencyProvider provider;
    late LogLevel originalLogLevel;

    MockNavigationService navigation() => provider.mockNavigationService;
    MockAuthService auth() => provider.mockAuthService;

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    /// Creates the coordinator for [authState] and [request], and returns it
    /// after the request is resolved.
    Future<AppCoordinator> show(
      AuthState authState,
      ConfigurationBase request, {
      List<RouteGuard> guards = const [],
    }) async {
      when(provider.mockAppCoordinatorDelegate.createGuards(any))
          .thenReturn(guards);
      when(auth().authState).thenAnswer(
        (_) => BehaviorSubject<AuthState>.seeded(authState),
      );
      when(navigation().routeRequestStream).thenAnswer(
        (_) => BehaviorSubject<ConfigurationBase>.seeded(request),
      );
      final coordinator = SutFactory.createAppCoordinator(provider: provider);
      await settle();
      return coordinator;
    }

    final signedIn = Authenticated(ModelFactory.createSession());
    const noSession = SignedOut(SignedOutReason.noSession);
    const expired = SignedOut(SignedOutReason.expired);
    const loggedOut = SignedOut(SignedOutReason.signedOut);
    const unknown = AuthUnknown();

    setUp(() async {
      originalLogLevel = boundaryLogLevel;
      provider = MockDependencyProvider();
      await SutFactory.initTestBed(provider: provider);
      when(provider.mockAppCoordinatorDelegate.routes).thenReturn([
        bind<PublicRoute>(PublicRoute.path, const PublicRoute(),
            access: RouteAccess.public),
        bind<GuestRoute>(GuestRoute.path, const GuestRoute(),
            access: RouteAccess.guestOnly),
        bind<CasesRoute>(CasesRoute.path, const CasesRoute()),
        bind<HomeRoute>(HomeRoute.path, const HomeRoute()),
        bind<CallbackRoute>(CallbackRoute.path, const CallbackRoute(),
            access: RouteAccess.public, transient: true),
        bind<RootRoute>(RootRoute.path, const RootRoute(),
            access: RouteAccess.public),
      ]);
      when(provider.mockAppCoordinatorDelegate.getLoginRoute())
          .thenReturn(const GuestRoute());
      when(provider.mockAppCoordinatorDelegate.getPostLoginDefaultRoute())
          .thenReturn(const HomeRoute());
    });

    tearDown(() {
      boundaryLogLevel = originalLogLevel;
    });

    group('access table', () {
      test('a signed-in user can open a public route', () async {
        final coordinator = await show(signedIn, const PublicRoute());

        expect(coordinator.baseConfiguration, const PublicRoute());
      });

      test('a signed-in user is sent from a guest-only route to the default',
          () async {
        final coordinator = await show(signedIn, const GuestRoute());

        expect(coordinator.baseConfiguration, const HomeRoute());
      });

      test('a signed-in user can open a protected route', () async {
        final coordinator = await show(signedIn, const CasesRoute());

        expect(coordinator.baseConfiguration, const CasesRoute());
      });

      test('with no session a public route is shown without a stored redirect',
          () async {
        final coordinator = await show(noSession, const PublicRoute());

        expect(coordinator.baseConfiguration, const PublicRoute());
        verifyNever(navigation().setPostAuthRedirect(any));
      });

      test(
          'with no session a guest-only route is shown without a stored redirect',
          () async {
        final coordinator = await show(noSession, const GuestRoute());

        expect(coordinator.baseConfiguration, const GuestRoute());
        verifyNever(navigation().setPostAuthRedirect(any));
      });

      test(
          'with no session a protected route is stored and the login route is shown',
          () async {
        final coordinator = await show(noSession, const CasesRoute());

        expect(coordinator.baseConfiguration, const GuestRoute());
        verify(navigation().setPostAuthRedirect(const CasesRoute())).called(1);
      });

      test(
          'with an expired session a protected route is stored and the login route is shown',
          () async {
        final coordinator = await show(expired, const CasesRoute());

        expect(coordinator.baseConfiguration, const GuestRoute());
        verify(navigation().setPostAuthRedirect(const CasesRoute())).called(1);
      });

      test(
          'when signed out by the user a protected route requests the login route',
          () async {
        final coordinator = await show(loggedOut, const CasesRoute());

        expect(coordinator.baseConfiguration, isNull);
        verify(navigation().redirectTo(const GuestRoute())).called(1);
        verifyNever(navigation().navigateTo(any));
        verifyNever(navigation().setPostAuthRedirect(any));
      });

      test('when signed out by the user a public route stays where it is',
          () async {
        final coordinator = await show(loggedOut, const PublicRoute());

        expect(coordinator.baseConfiguration, const PublicRoute());
        verifyNever(navigation().navigateTo(any));
      });

      test('while auth is unknown the request is shown and no guard runs',
          () async {
        final guard = RecordingGuard();

        final coordinator =
            await show(unknown, const CasesRoute(), guards: [guard]);

        expect(coordinator.baseConfiguration, const CasesRoute());
        expect(guard.seen, isEmpty);
      });
    });

    test('the root goes to the default route when signed in', () async {
      final coordinator = await show(signedIn, const RootRoute());

      expect(coordinator.baseConfiguration, const HomeRoute());
    });

    group('guards', () {
      test('guards run in order and the first redirect wins', () async {
        final a = RecordingGuard();
        final b = RecordingGuard((route) {
          if (route is CasesRoute) {
            return Future<GuardResult>(
              () => const GuardResult.redirect(PublicRoute()),
            );
          }
          return const GuardResult.allow();
        });
        final c = RecordingGuard();

        final coordinator =
            await show(signedIn, const CasesRoute(), guards: [a, b, c]);

        expect(coordinator.baseConfiguration, const PublicRoute());
        expect(a.seen, [const CasesRoute(), const PublicRoute()]);
        expect(b.seen, [const CasesRoute(), const PublicRoute()]);
        expect(c.seen, [const PublicRoute()]);
      });

      test('a guard redirect goes through the access step', () async {
        final guard = RecordingGuard(
          (route) => route is PublicRoute
              ? const GuardResult.redirect(CasesRoute())
              : const GuardResult.allow(),
        );

        final coordinator =
            await show(noSession, const PublicRoute(), guards: [guard]);

        expect(coordinator.baseConfiguration, const GuestRoute());
        verify(navigation().setPostAuthRedirect(const CasesRoute())).called(1);
      });

      test('guards see the post-auth redirect target', () async {
        when(navigation().consumePostAuthRedirect())
            .thenAnswer((_) async => const CasesRoute());
        final guard = RecordingGuard();

        final coordinator =
            await show(signedIn, const HomeRoute(), guards: [guard]);

        expect(guard.seen, [const CasesRoute()]);
        expect(coordinator.baseConfiguration, const CasesRoute());
        verify(navigation().consumePostAuthRedirect()).called(1);
      });

      test('a redirect loop ends on an error page', () async {
        final guard = RecordingGuard(
          (route) => route is PublicRoute
              ? const GuardResult.redirect(CasesRoute())
              : const GuardResult.redirect(PublicRoute()),
        );

        final coordinator =
            await show(signedIn, const CasesRoute(), guards: [guard]);

        expect(coordinator.baseConfiguration,
            errorRouteWith('error.navigation.redirectLoop'));
        expect(guard.seen, hasLength(6));
      });

      test('a guard that throws gives an error page', () async {
        boundaryLogLevel = LogLevel.critical;
        final guard = RecordingGuard((route) {
          if (route is CasesRoute) throw StateError('policy');
          return const GuardResult.allow();
        });

        final coordinator =
            await show(signedIn, const CasesRoute(), guards: [guard]);

        expect(coordinator.baseConfiguration,
            errorRouteWith('error.navigation.guardFailed'));
      });

      test('a guard that fails asynchronously gives an error page', () async {
        boundaryLogLevel = LogLevel.critical;
        final guard = RecordingGuard((route) {
          if (route is CasesRoute) {
            return Future<GuardResult>.error(StateError('policy'));
          }
          return const GuardResult.allow();
        });

        final coordinator =
            await show(signedIn, const CasesRoute(), guards: [guard]);

        expect(coordinator.baseConfiguration,
            errorRouteWith('error.navigation.guardFailed'));
      });

      test('guards are created once', () async {
        final navStream = BehaviorSubject<ConfigurationBase>();
        addTearDown(navStream.close);
        when(provider.mockAppCoordinatorDelegate.createGuards(any))
            .thenReturn([RecordingGuard()]);
        when(auth().authState).thenAnswer(
          (_) => BehaviorSubject<AuthState>.seeded(signedIn),
        );
        when(navigation().routeRequestStream)
            .thenAnswer((_) => navStream.stream);
        final coordinator = SutFactory.createAppCoordinator(provider: provider);

        for (final route in const [
          PublicRoute(),
          CasesRoute(),
          HomeRoute(),
        ]) {
          navStream.add(route);
          await settle();
        }

        expect(coordinator.baseConfiguration, const HomeRoute());
        verify(provider.mockAppCoordinatorDelegate.createGuards(any)).called(1);
      });
    });
  });
}
