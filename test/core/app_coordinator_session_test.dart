// Test Plan:
//
// group: 'Unauthenticated User Scenarios'
//   - test: should allow navigation to an unprotected route
//   - test: should store redirect and navigate to login when a protected route is requested
//   - test: should navigate to login page when auth state is LoggedOut without a reset email
//   - test: should navigate to reset password page when auth state is LoggedOut with a reset email
//
// group: 'Authenticated User Scenarios'
//   - test: should allow navigation to a standard protected route
//   - test: should redirect to the post-login default route when a public-only route (e.g., login) is requested
//   - test: should redirect to the post-auth URL after a successful login
//   - test: should navigate to post-login default route when the root path is requested
//   - test: should allow navigation to the logout route

import 'package:boundary/router.dart';
import 'package:boundary/service/auth_service.dart';
import 'package:boundary/utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/mock_dependency_provider.dart';
import '../helpers/model_factory.dart';
import '../helpers/sut_factory.dart';

// Fakes for type-safe route comparison
class FakeUnprotectedRoute extends ConfigurationBase {
  @override
  bool get protected => false;
  @override
  String get pathTemplate => '/unprotected';
}

class FakeProtectedRoute extends ConfigurationBase {
  @override
  bool get protected => true;
  @override
  String get pathTemplate => '/protected';
}

class FakeLoginRoute extends ConfigurationBase {
  @override
  bool get protected => false;
  @override
  String get pathTemplate => '/login';
}

class FakeResetPasswordRoute extends ConfigurationBase {
  @override
  bool get protected => false;
  @override
  String get pathTemplate => '/reset-password';
}

class FakePostLoginDefaultRoute extends ConfigurationBase {
  @override
  bool get protected => true;
  @override
  String get pathTemplate => '/home';
}

class FakeRootRoute extends ConfigurationBase {
  @override
  bool get isRoot => true;
  @override
  String get pathTemplate => '/';
}

class FakeLogoutRoute extends ConfigurationBase {
  @override
  bool get protected => true;
  @override
  String get pathTemplate => '/logout';
}

void main() {
  group('AppCoordinator Session Flows', () {
    late MockDependencyProvider provider;

    setUp(() async {
      provider = MockDependencyProvider();
      await SutFactory.initTestBed(provider: provider);
    });

    group('Unauthenticated User Scenarios', () {
      test(
        'should allow navigation to an unprotected route',
        () async {
          // Arrange
          final unprotectedRoute = FakeUnprotectedRoute();

          when(provider.mockAuthService.userStream).thenAnswer(
            (_) => BehaviorSubject.seeded(const Failure(NoSessionStored())),
          );
          when(provider.mockNavigationService.routeRequestStream).thenAnswer(
            (_) => BehaviorSubject.seeded(unprotectedRoute),
          );

          // Act
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          await Future.delayed(Duration.zero);

          // Assert
          expect(coordinator.baseConfiguration, equals(unprotectedRoute));
          verifyNever(
            provider.mockNavigationService.setPostAuthRedirect(any),
          );
        },
      );

      test(
        'should store redirect and navigate to login when a protected route is requested',
        () async {
          // Arrange
          final protectedRoute = FakeProtectedRoute();
          final loginRoute = FakeLoginRoute();

          when(provider.mockAuthService.userStream).thenAnswer(
            (_) => BehaviorSubject.seeded(const Failure(NoSessionStored())),
          );
          when(provider.mockNavigationService.routeRequestStream).thenAnswer(
            (_) => BehaviorSubject.seeded(protectedRoute),
          );
          when(provider.mockAppCoordinatorDelegate.getLoginRoute())
              .thenReturn(loginRoute);

          // Act
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          await Future.delayed(Duration.zero);

          // Assert
          verify(
            provider.mockNavigationService.setPostAuthRedirect(protectedRoute),
          ).called(1);
          expect(coordinator.baseConfiguration, equals(loginRoute));
        },
      );

      test(
        'should navigate to login page when auth state is LoggedOut without a reset email',
        () async {
          // Arrange
          final loginRoute = FakeLoginRoute();
          when(provider.mockAuthService.userStream).thenAnswer(
            (_) => BehaviorSubject.seeded(const Failure(LoggedOut())),
          );
          when(provider.mockNavigationService.routeRequestStream).thenAnswer(
            (_) => BehaviorSubject.seeded(FakeProtectedRoute()),
          );
          when(provider.mockAppCoordinatorDelegate.getLoginRoute())
              .thenReturn(loginRoute);

          // Act
          SutFactory.createAppCoordinator(provider: provider);
          await Future.delayed(Duration.zero);

          // Assert
          verify(provider.mockAuthService
                  .clearLoggedOutStateAndPrepareForPolicyCheck())
              .called(1);
          verify(provider.mockNavigationService.navigateTo(loginRoute))
              .called(1);
        },
      );

      test(
        'should navigate to reset password page when auth state is LoggedOut with a reset email',
        () async {
          // Arrange
          const testEmail = 'test@example.com';
          final resetPasswordRoute = FakeResetPasswordRoute();
          when(provider.mockAuthService.userStream).thenAnswer(
            (_) => BehaviorSubject.seeded(
                const Failure(LoggedOut(emailForResetPassword: testEmail))),
          );
          when(provider.mockNavigationService.routeRequestStream).thenAnswer(
            (_) => BehaviorSubject.seeded(FakeProtectedRoute()),
          );
          when(provider.mockAppCoordinatorDelegate
                  .getResetPasswordRoute(email: testEmail))
              .thenReturn(resetPasswordRoute);

          // Act
          SutFactory.createAppCoordinator(provider: provider);
          await Future.delayed(Duration.zero);

          // Assert
          verify(provider.mockAuthService
                  .clearLoggedOutStateAndPrepareForPolicyCheck())
              .called(1);
          verify(provider.mockNavigationService.navigateTo(resetPasswordRoute))
              .called(1);
        },
      );
    });

    group('Authenticated User Scenarios', () {
      test(
        'should allow navigation to a standard protected route',
        () async {
          // Arrange
          final protectedRoute = FakeProtectedRoute();
          when(provider.mockAuthService.userStream).thenAnswer(
            (_) => BehaviorSubject.seeded(Data(ModelFactory.createUser())),
          );
          when(provider.mockNavigationService.routeRequestStream).thenAnswer(
            (_) => BehaviorSubject.seeded(protectedRoute),
          );
          when(provider.mockNavigationService.consumePostAuthRedirect())
              .thenAnswer((_) async => null);
          when(provider.mockAppCoordinatorDelegate.isPublicOnlyRoute(any))
              .thenReturn(false);

          // Act
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          await Future.delayed(Duration.zero);

          // Assert
          expect(coordinator.baseConfiguration, equals(protectedRoute));
        },
      );

      test(
        'should redirect to the post-login default route when a public-only route is requested',
        () async {
          // Arrange
          final loginRoute = FakeLoginRoute();
          final defaultRoute = FakePostLoginDefaultRoute();
          when(provider.mockAuthService.userStream).thenAnswer(
            (_) => BehaviorSubject.seeded(Data(ModelFactory.createUser())),
          );
          when(provider.mockNavigationService.routeRequestStream).thenAnswer(
            (_) => BehaviorSubject.seeded(loginRoute),
          );
          when(provider.mockAppCoordinatorDelegate
                  .isPublicOnlyRoute(loginRoute))
              .thenReturn(true);
          when(provider.mockAppCoordinatorDelegate.getPostLoginDefaultRoute())
              .thenReturn(defaultRoute);

          // Act
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          await Future.delayed(Duration.zero);

          // Assert
          expect(coordinator.baseConfiguration, equals(defaultRoute));
        },
      );

      test(
        'should redirect to the post-auth URL after a successful login',
        () async {
          // Arrange
          final protectedRoute = FakeProtectedRoute();
          final loginRoute = FakeLoginRoute();

          final authStreamController = BehaviorSubject<AsyncResult<User>>();
          final navStreamController = BehaviorSubject<ConfigurationBase>();

          when(provider.mockAuthService.userStream)
              .thenAnswer((_) => authStreamController.stream);
          when(provider.mockNavigationService.routeRequestStream)
              .thenAnswer((_) => navStreamController.stream);
          when(provider.mockAppCoordinatorDelegate.getLoginRoute())
              .thenReturn(loginRoute);
          when(provider.mockNavigationService.consumePostAuthRedirect())
              .thenAnswer((_) async => protectedRoute);

          // Act
          // 1. Create the coordinator and push the initial unauthenticated state
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          authStreamController.add(const Failure(NoSessionStored()));
          navStreamController.add(protectedRoute);

          // Wait for the first reconciliation (user is sent to login)
          await Future.delayed(Duration.zero);

          // 2. Simulate a successful login by pushing the new auth state
          authStreamController.add(Data(ModelFactory.createUser()));

          // Wait for the second reconciliation (user is redirected)
          await Future.delayed(Duration.zero);

          // Assert
          verify(provider.mockNavigationService.consumePostAuthRedirect())
              .called(1);
          expect(coordinator.baseConfiguration, equals(protectedRoute));
        },
      );

      test(
        'should navigate to post-login default route when the root path is requested',
        () async {
          // Arrange
          final rootRoute = FakeRootRoute();
          final defaultRoute = FakePostLoginDefaultRoute();

          when(provider.mockAuthService.userStream).thenAnswer(
            (_) => BehaviorSubject.seeded(Data(ModelFactory.createUser())),
          );
          when(provider.mockNavigationService.routeRequestStream).thenAnswer(
            (_) => BehaviorSubject.seeded(rootRoute),
          );
          when(provider.mockAppCoordinatorDelegate.getPostLoginDefaultRoute())
              .thenReturn(defaultRoute);

          // Act
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          await Future.delayed(Duration.zero);

          // Assert
          expect(coordinator.baseConfiguration, equals(defaultRoute));
        },
      );

      test(
        'should allow navigation to the logout route',
        () async {
          // Arrange
          final logoutRoute = FakeLogoutRoute();
          when(provider.mockAuthService.userStream).thenAnswer(
            (_) => BehaviorSubject.seeded(Data(ModelFactory.createUser())),
          );
          when(provider.mockNavigationService.routeRequestStream).thenAnswer(
            (_) => BehaviorSubject.seeded(logoutRoute),
          );
          when(provider.mockAppCoordinatorDelegate.isLogoutRoute(logoutRoute))
              .thenReturn(true);

          // Act
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          await Future.delayed(Duration.zero);

          // Assert
          expect(coordinator.baseConfiguration, equals(logoutRoute));
        },
      );
    });
  });
}
