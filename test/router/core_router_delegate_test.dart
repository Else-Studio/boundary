// Test Plan:
//
// group: 'CoreRouterDelegate system back'
//   - test: system back on a modal closes it through NavigationService
//   - test: system back without a modal does not dismiss anything
//   - test: system back on a modal built as a plain page does not dismiss
//   - test: the coordinator closing a modal does not dismiss it again

import 'package:boundary/boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/mock_dependency_provider.dart';
import '../helpers/mocks.mocks.dart';
import '../helpers/model_factory.dart';
import '../helpers/sut_factory.dart';

class FakeBaseRoute extends ConfigurationBase {
  @override
  String get pathTemplate => '/base';
}

class FakeModalRoute extends ConfigurationBase {
  @override
  bool get isModal => true;
  @override
  String get pathTemplate => '/modal';
}

class PlainPageBuilder implements RouterPageBuilder {
  @override
  Page buildBasePage(
          BuildContext context, ConfigurationBase config, Widget content) =>
      MaterialPage(child: content);

  @override
  Page buildModalPage(
          BuildContext context, ConfigurationBase config, Widget content) =>
      MaterialPage(child: content);
}

class TestPageBuilder implements RouterPageBuilder {
  @override
  Page buildBasePage(
          BuildContext context, ConfigurationBase config, Widget content) =>
      MaterialPage(child: content);

  @override
  Page buildModalPage(
          BuildContext context, ConfigurationBase config, Widget content) =>
      TransparentModalPage(child: content);
}

void main() {
  group('CoreRouterDelegate system back', () {
    late MockDependencyProvider provider;
    late BehaviorSubject<AsyncResult<User>> authStream;
    late BehaviorSubject<ConfigurationBase> navStream;
    late AppCoordinator coordinator;
    late CoreRouterDelegate delegate;

    setUp(() async {
      provider = MockDependencyProvider();
      await SutFactory.initTestBed(provider: provider);

      authStream = BehaviorSubject.seeded(Data(ModelFactory.createUser()));
      navStream = BehaviorSubject();
      when(provider.mockAuthService.userStream)
          .thenAnswer((_) => authStream.stream);
      when(provider.mockAuthService.isLoading).thenReturn(false);
      when(provider.mockNavigationService.routeRequestStream)
          .thenAnswer((_) => navStream.stream);
      when(provider.mockAppCoordinatorDelegate.routes).thenReturn([
        RouteBinding<FakeBaseRoute, MockController>(
          path: '/base',
          parse: (_) => FakeBaseRoute(),
          controller: (_) => provider.mockController,
          page: const SizedBox(),
        ),
        RouteBinding<FakeModalRoute, MockController>(
          path: '/modal',
          parse: (_) => FakeModalRoute(),
          controller: (_) => MockController(),
          page: const SizedBox(),
        ),
      ]);

      coordinator = SutFactory.createAppCoordinator(provider: provider);
      delegate = CoreRouterDelegate(
        appCoordinator: coordinator,
        pageBuilder: TestPageBuilder(),
      );
    });

    tearDown(() {
      authStream.close();
      navStream.close();
    });

    Future<void> emit(WidgetTester tester, ConfigurationBase route) async {
      navStream.add(route);
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
    }

    Future<void> pumpRouter(WidgetTester tester) async {
      await tester
          .pumpWidget(MaterialApp(home: Router(routerDelegate: delegate)));
      await tester.pump();
    }

    testWidgets('system back on a modal closes it through NavigationService',
        (tester) async {
      await emit(tester, FakeBaseRoute());
      await emit(tester, FakeModalRoute());
      await pumpRouter(tester);
      expect(coordinator.modalConfiguration, isA<FakeModalRoute>());

      await delegate.popRoute();
      await tester.pumpAndSettle();

      verify(provider.mockNavigationService.dismissModal()).called(1);
    });

    testWidgets('system back without a modal does not dismiss anything',
        (tester) async {
      await emit(tester, FakeBaseRoute());
      await pumpRouter(tester);

      final handled = await delegate.popRoute();
      await tester.pumpAndSettle();

      expect(handled, isFalse);
      verifyNever(provider.mockNavigationService.dismissModal());
    });

    testWidgets('system back on a modal built as a plain page does not dismiss',
        (tester) async {
      delegate = CoreRouterDelegate(
        appCoordinator: coordinator,
        pageBuilder: PlainPageBuilder(),
      );
      await emit(tester, FakeBaseRoute());
      await emit(tester, FakeModalRoute());
      await pumpRouter(tester);
      expect(coordinator.modalConfiguration, isA<FakeModalRoute>());

      final handled = await delegate.popRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      verifyNever(provider.mockNavigationService.dismissModal());
    });

    testWidgets('the coordinator closing a modal does not dismiss it again',
        (tester) async {
      await emit(tester, FakeBaseRoute());
      await emit(tester, FakeModalRoute());
      await pumpRouter(tester);
      expect(coordinator.modalConfiguration, isA<FakeModalRoute>());

      await emit(tester, FakeBaseRoute());
      await tester.pump();

      expect(coordinator.modalConfiguration, isNull);
      verifyNever(provider.mockNavigationService.dismissModal());
    });
  });
}
