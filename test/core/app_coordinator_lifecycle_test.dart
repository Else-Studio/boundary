// Test Plan:
//
// group: 'State Transition and Controller Lifecycle'
//   - test: should preserve the original navigation request while auth state is unknown
//   - test: should set modalConfiguration and preserve baseConfiguration when a modal route is requested
//   - test: should create a new base controller when the base configuration changes
//   - test: should dispose the old base controller when the base configuration changes
//   - test: should create a new modal controller when a modal is requested
//   - test: should dispose the modal controller when navigating away from a modal
//
// group: 'Error Handling'
//   - test: an error on the auth stream shows the session error page
//   - test: while auth is unknown the base content is the loading scaffold
//   - test: should default to a known good route if the delegate returns null for a base configuration

import 'package:boundary/controller.dart';
import 'package:boundary/route_table.dart';
import 'package:boundary/router.dart';
import 'package:boundary/service/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/mock_dependency_provider.dart';
import '../helpers/mocks.mocks.dart';
import '../helpers/model_factory.dart';
import '../helpers/sut_factory.dart';

// Fakes for type-safe route comparison
class FakeBaseRoute extends ConfigurationBase {
  @override
  String get pathTemplate => '/base';
}

class FakeOtherBaseRoute extends ConfigurationBase {
  @override
  String get pathTemplate => '/other-base';
}

class FakeModalRoute extends ConfigurationBase {
  @override
  bool get isModal => true;
  @override
  String get pathTemplate => '/modal';
}

/// A binding for [R] that hands out [controller] and counts how often the
/// coordinator asked for it.
class CountingBinding<R extends ConfigurationBase> {
  CountingBinding(String path, R Function() route, this.controller) {
    binding = RouteBinding<R, Controller>(
      path: path,
      parse: (_) => route(),
      controller: (_) {
        created++;
        return controller;
      },
      page: const SizedBox(),
    );
  }

  final Controller controller;
  late final RouteBinding<R, Controller> binding;
  int created = 0;
}

CountingBinding<FakeBaseRoute> baseBinding(Controller controller) =>
    CountingBinding(
        FakeBaseRoute().pathTemplate, FakeBaseRoute.new, controller);

CountingBinding<FakeOtherBaseRoute> otherBaseBinding(Controller controller) =>
    CountingBinding(
        FakeOtherBaseRoute().pathTemplate, FakeOtherBaseRoute.new, controller);

CountingBinding<FakeModalRoute> modalBinding(Controller controller) =>
    CountingBinding(
        FakeModalRoute().pathTemplate, FakeModalRoute.new, controller);

void main() {
  group('AppCoordinator Lifecycle and Error Handling', () {
    late MockDependencyProvider provider;
    late BehaviorSubject<AuthState> authStreamController;
    late BehaviorSubject<ConfigurationBase> navStreamController;

    setUp(() async {
      provider = MockDependencyProvider();
      await SutFactory.initTestBed(provider: provider);

      authStreamController = BehaviorSubject();
      navStreamController = BehaviorSubject();

      // Default stubbing to use the controllers
      when(provider.mockAuthService.authState)
          .thenAnswer((_) => authStreamController.stream);
      when(provider.mockNavigationService.routeRequestStream)
          .thenAnswer((_) => navStreamController.stream);
    });

    tearDown(() {
      authStreamController.close();
      navStreamController.close();
    });

    group('State Transition and Controller Lifecycle', () {
      test(
        'should preserve the original navigation request while auth state is unknown',
        () async {
          // Arrange
          final routeRequest = FakeBaseRoute();
          authStreamController.add(const AuthUnknown());
          when(provider.mockAppCoordinatorDelegate.routes).thenReturn([
            baseBinding(provider.mockController).binding,
          ]);

          // Act
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          navStreamController.add(routeRequest);
          await Future.delayed(Duration.zero); // Allow stream to process

          // Assert
          expect(coordinator.baseConfiguration, equals(routeRequest));
        },
      );

      test(
        'should set modalConfiguration and preserve baseConfiguration when a modal route is requested',
        () async {
          // Arrange
          final baseRoute = FakeBaseRoute();
          final modalRoute = FakeModalRoute();
          authStreamController.add(Authenticated(ModelFactory.createSession()));
          when(provider.mockAppCoordinatorDelegate.routes).thenReturn([
            baseBinding(provider.mockController).binding,
            modalBinding(MockController()).binding,
          ]);

          // Act
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          navStreamController.add(baseRoute);
          await Future.delayed(Duration.zero);

          navStreamController.add(modalRoute);
          await Future.delayed(Duration.zero);

          // Assert
          expect(coordinator.baseConfiguration, isA<FakeBaseRoute>());
          expect(coordinator.modalConfiguration, isA<FakeModalRoute>());
        },
      );

      test(
        'should create a new base controller when the base configuration changes',
        () async {
          // Arrange
          final routeA = FakeBaseRoute();
          final routeB = FakeOtherBaseRoute();
          final bindingA = baseBinding(provider.mockController);
          final bindingB = otherBaseBinding(MockController());
          authStreamController.add(Authenticated(ModelFactory.createSession()));

          when(provider.mockAppCoordinatorDelegate.routes)
              .thenReturn([bindingA.binding, bindingB.binding]);

          // Act
          SutFactory.createAppCoordinator(provider: provider);
          navStreamController.add(routeA);
          await Future.delayed(Duration.zero);

          navStreamController.add(routeB);
          await Future.delayed(Duration.zero);

          // Assert
          expect(bindingA.created, 1);
          expect(bindingB.created, 1);
        },
      );

      test(
        'should dispose the old base controller when the base configuration changes',
        () async {
          // Arrange
          final routeA = FakeBaseRoute();
          final routeB = FakeOtherBaseRoute();
          final controllerA = MockController();
          final controllerB = MockController();
          authStreamController.add(Authenticated(ModelFactory.createSession()));

          when(provider.mockAppCoordinatorDelegate.routes).thenReturn([
            baseBinding(controllerA).binding,
            otherBaseBinding(controllerB).binding,
          ]);

          // Act
          SutFactory.createAppCoordinator(provider: provider);
          navStreamController.add(routeA);
          await Future.delayed(Duration.zero);

          navStreamController.add(routeB);
          await Future.delayed(Duration.zero);

          // Assert
          verify(controllerA.dispose()).called(1);
          verifyNever(controllerB.dispose());
        },
      );

      test(
        'should create a new modal controller when a modal is requested',
        () async {
          // Arrange
          final baseRoute = FakeBaseRoute();
          final modalRoute = FakeModalRoute();
          final modalController = MockController();
          authStreamController.add(Authenticated(ModelFactory.createSession()));

          final modalBindingUnderTest = modalBinding(modalController);
          when(provider.mockAppCoordinatorDelegate.routes).thenReturn([
            baseBinding(provider.mockController).binding,
            modalBindingUnderTest.binding,
          ]);

          // Act
          SutFactory.createAppCoordinator(provider: provider);
          navStreamController.add(baseRoute);
          await Future.delayed(Duration.zero);

          navStreamController.add(modalRoute);
          await Future.delayed(Duration.zero);

          // Assert
          expect(modalBindingUnderTest.created, 1);
        },
      );

      test(
        'should dispose the modal controller when navigating away from a modal',
        () async {
          // Arrange
          final baseRoute = FakeBaseRoute();
          final modalRoute = FakeModalRoute();
          final nextBaseRoute = FakeOtherBaseRoute();
          final modalController = MockController();
          authStreamController.add(Authenticated(ModelFactory.createSession()));

          when(provider.mockAppCoordinatorDelegate.routes).thenReturn([
            baseBinding(provider.mockController).binding,
            modalBinding(modalController).binding,
            otherBaseBinding(MockController()).binding,
          ]);

          // Act
          SutFactory.createAppCoordinator(provider: provider);
          navStreamController.add(baseRoute);
          await Future.delayed(Duration.zero);

          navStreamController.add(modalRoute);
          await Future.delayed(Duration.zero);

          navStreamController.add(nextBaseRoute);
          await Future.delayed(Duration.zero);

          // Assert
          verify(modalController.dispose()).called(1);
        },
      );
    });

    group('Error Handling', () {
      test(
        'an error on the auth stream shows the session error page',
        () async {
          // Arrange
          authStreamController.addError(StateError('broken'));
          when(provider.mockAppCoordinatorDelegate.getLoginRoute())
              .thenReturn(FakeBaseRoute());
          when(provider.mockAppCoordinatorDelegate.routes).thenReturn([
            baseBinding(provider.mockController).binding,
          ]);

          // Act
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          navStreamController.add(FakeBaseRoute());
          await Future.delayed(Duration.zero);

          // Assert
          final route = coordinator.baseConfiguration;
          expect(route, isA<ErrorRoute>());
          expect((route as ErrorRoute).isSessionTermination, isTrue);
          expect(route.message, 'error.session.unexpected');
        },
      );

      test(
        'while auth is unknown the base content is the loading scaffold',
        () async {
          // Arrange
          var errorControllersCreated = 0;
          authStreamController.add(const AuthUnknown());
          when(provider.mockAppCoordinatorDelegate.routes).thenReturn([
            baseBinding(provider.mockController).binding,
            RouteBinding<ErrorRoute, Controller>(
              path: ErrorRoute.path,
              parse: (p) => ErrorRoute(message: p['message'] ?? ''),
              controller: (_) {
                errorControllersCreated++;
                return provider.mockController;
              },
              page: const SizedBox(),
            ),
          ]);

          // Act
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          await Future.delayed(Duration.zero);
          final content = coordinator.getBaseContentWidget();

          // Assert
          expect(content, isA<Scaffold>());
          expect(
              content.key, const ValueKey('AppCoordinatorLoadingBase-Generic'));
          expect(errorControllersCreated, 0);
        },
      );
    });
  });
}
