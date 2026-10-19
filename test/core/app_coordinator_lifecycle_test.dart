// Test Plan:
//
// group: 'State Transition and Controller Lifecycle'
//   - test: should preserve the original navigation request while auth state is Loading
//   - test: should set modalConfiguration and preserve baseConfiguration when a modal route is requested
//   - test: should create a new base controller when the base configuration changes
//   - test: should dispose the old base controller when the base configuration changes
//   - test: should create a new modal controller when a modal is requested
//   - test: should dispose the modal controller when navigating away from a modal
//
// group: 'Error Handling'
//   - test: should set an ErrorRoute configuration for unhandled AuthErrors
//   - test: should default to a known good route if the delegate returns null for a base configuration

import 'package:boundary/router.dart';
import 'package:boundary/service/auth_service.dart';
import 'package:boundary/utils.dart';
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
  Uri get uri => Uri.parse('/base');
}

class FakeOtherBaseRoute extends ConfigurationBase {
  @override
  Uri get uri => Uri.parse('/other-base');
}

class FakeModalRoute extends ConfigurationBase {
  @override
  bool get isModal => true;
  @override
  Uri get uri => Uri.parse('/modal');
}

void main() {
  group('AppCoordinator Lifecycle and Error Handling', () {
    late MockDependencyProvider provider;
    late BehaviorSubject<AsyncResult<User>> authStreamController;
    late BehaviorSubject<ConfigurationBase> navStreamController;

    setUp(() async {
      provider = MockDependencyProvider();
      await SutFactory.initTestBed(provider: provider);

      authStreamController = BehaviorSubject();
      navStreamController = BehaviorSubject();

      // Default stubbing to use the controllers
      when(provider.mockAuthService.userStream)
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
        'should preserve the original navigation request while auth state is Loading',
        () async {
          // Arrange
          final routeRequest = FakeBaseRoute();
          authStreamController.add(const Loading());

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
          authStreamController.add(Data(ModelFactory.createUser()));

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
          final controllerA = provider.mockController;
          final controllerB = MockController(); // A different mock instance
          authStreamController.add(Data(ModelFactory.createUser()));

          when(provider.mockAppCoordinatorDelegate
                  .createControllerForConfiguration(routeA, any))
              .thenReturn(controllerA);
          when(provider.mockAppCoordinatorDelegate
                  .createControllerForConfiguration(routeB, any))
              .thenReturn(controllerB);

          // Act
          SutFactory.createAppCoordinator(provider: provider);
          navStreamController.add(routeA);
          await Future.delayed(Duration.zero);

          navStreamController.add(routeB);
          await Future.delayed(Duration.zero);

          // Assert
          verify(provider.mockAppCoordinatorDelegate
                  .createControllerForConfiguration(routeA, any))
              .called(1);
          verify(provider.mockAppCoordinatorDelegate
                  .createControllerForConfiguration(routeB, any))
              .called(1);
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
          authStreamController.add(Data(ModelFactory.createUser()));

          when(provider.mockAppCoordinatorDelegate
                  .createControllerForConfiguration(routeA, any))
              .thenReturn(controllerA);
          when(provider.mockAppCoordinatorDelegate
                  .createControllerForConfiguration(routeB, any))
              .thenReturn(controllerB);
          when(provider.mockAppCoordinatorDelegate
                  .shouldDisposeController(controllerA))
              .thenReturn(true);

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
          authStreamController.add(Data(ModelFactory.createUser()));

          when(provider.mockAppCoordinatorDelegate
                  .createControllerForConfiguration(modalRoute, any))
              .thenReturn(modalController);

          // Act
          SutFactory.createAppCoordinator(provider: provider);
          navStreamController.add(baseRoute);
          await Future.delayed(Duration.zero);

          navStreamController.add(modalRoute);
          await Future.delayed(Duration.zero);

          // Assert
          verify(provider.mockAppCoordinatorDelegate
                  .createControllerForConfiguration(modalRoute, any))
              .called(1);
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
          authStreamController.add(Data(ModelFactory.createUser()));

          when(provider.mockAppCoordinatorDelegate
                  .createControllerForConfiguration(modalRoute, any))
              .thenReturn(modalController);

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
        'should set an ErrorRoute configuration for unhandled AuthErrors',
        () async {
          // Arrange
          authStreamController
              .add(const Error(TokenVerificationFailed(message: 'test')));

          // Act
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          navStreamController.add(FakeBaseRoute());
          await Future.delayed(Duration.zero);

          // Assert
          expect(coordinator.baseConfiguration, isA<ErrorRoute>());
        },
      );

      test(
        'should display a fallback error widget if base controller is null and auth is not loading',
        () async {
          // Arrange
          when(provider.mockAuthService.isLoading).thenReturn(false);
          authStreamController.add(Data(ModelFactory.createUser()));
          final mockErrorController = MockController();

          when(provider.mockAppCoordinatorDelegate
                  .createControllerForConfiguration(any, any))
              .thenAnswer((invocation) {
            final config = invocation.positionalArguments[0];
            if (config is ErrorRoute) {
              return mockErrorController;
            }
            // Return the default for other types
            return provider.mockController;
          });
          when(provider.mockAppCoordinatorDelegate
                  .mapControllerToWidget(mockErrorController))
              .thenReturn(const SizedBox.shrink());

          // Act
          final coordinator =
              SutFactory.createAppCoordinator(provider: provider);
          // Do not push a nav event, so baseConfiguration remains null
          await Future.delayed(Duration.zero);
          coordinator.getBaseContentWidget();

          // Assert
          final captured = verify(provider.mockAppCoordinatorDelegate
                  .createControllerForConfiguration(captureAny, any))
              .captured;
          expect(captured.single, isA<ErrorRoute>());
          verify(provider.mockAppCoordinatorDelegate
                  .mapControllerToWidget(mockErrorController))
              .called(1);
        },
      );
    });
  });
}
