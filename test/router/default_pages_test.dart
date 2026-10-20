// Test Plan:
//
// group: 'Default error and not-found pages'
//   - test: an unbound NotFoundRoute shows the default page and Back goes back
//   - test: an unbound ErrorRoute shows the default page and Back goes back
//   - test: an app binding replaces a default page

import 'package:boundary/boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/mock_dependency_provider.dart';
import '../helpers/model_factory.dart';
import '../helpers/sut_factory.dart';

class CaseRoute extends ConfigurationBase {
  static const String path = '/cases/:id';

  const CaseRoute(this.id);

  final int id;

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => {'id': '$id'};
}

class FakeController extends Controller<void> {
  @override
  void handleAction(void action) {}
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

final caseBinding = RouteBinding<CaseRoute, FakeController>(
  path: CaseRoute.path,
  parse: (p) => CaseRoute(int.parse(p['id']!)),
  controller: (_) => FakeController(),
  page: const SizedBox(),
);

final appNotFoundBinding = RouteBinding<NotFoundRoute, FakeController>(
  path: NotFoundRoute.path,
  parse: (_) => const NotFoundRoute(NotFoundRoute.path),
  controller: (_) => FakeController(),
  page: const Text('custom 404'),
);

void main() {
  group('Default error and not-found pages', () {
    late MockDependencyProvider provider;
    late BehaviorSubject<AuthState> authStream;
    late BehaviorSubject<ConfigurationBase> navStream;
    late AppCoordinator coordinator;
    late CoreRouterDelegate delegate;

    setUp(() async {
      provider = MockDependencyProvider();
      await SutFactory.initTestBed(provider: provider);

      authStream =
          BehaviorSubject.seeded(Authenticated(ModelFactory.createSession()));
      navStream = BehaviorSubject();
      when(provider.mockAuthService.authState)
          .thenAnswer((_) => authStream.stream);
      when(provider.mockNavigationService.routeRequestStream)
          .thenAnswer((_) => navStream.stream);
    });

    tearDown(() {
      authStream.close();
      navStream.close();
    });

    void createRouter(List<RouteBinding> routes) {
      when(provider.mockAppCoordinatorDelegate.routes).thenReturn(routes);
      coordinator = SutFactory.createAppCoordinator(provider: provider);
      delegate = CoreRouterDelegate(
        appCoordinator: coordinator,
        pageBuilder: PlainPageBuilder(),
      );
    }

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

    Future<void> tapBack(WidgetTester tester) async {
      await tester.tap(find.text('Back'));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
    }

    testWidgets('an unbound not-found route shows the default page',
        (tester) async {
      createRouter([caseBinding]);

      await emit(tester, const NotFoundRoute('/nowhere'));
      await pumpRouter(tester);

      expect(find.text('Page not found'), findsOneWidget);
      expect(find.text('/nowhere'), findsOneWidget);

      await tapBack(tester);

      verify(provider.mockNavigationService.navigateBackOrLogin()).called(1);
    });

    testWidgets('an unbound error route shows the default page',
        (tester) async {
      createRouter([caseBinding]);

      await emit(tester, const ErrorRoute(message: 'error.session.unexpected'));
      await pumpRouter(tester);

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('error.session.unexpected'), findsOneWidget);

      await tapBack(tester);

      verify(provider.mockNavigationService.navigateBackOrLogin()).called(1);
    });

    testWidgets('an app binding replaces a default page', (tester) async {
      createRouter([caseBinding, appNotFoundBinding]);

      await emit(tester, const NotFoundRoute('/x'));
      await pumpRouter(tester);

      expect(find.text('custom 404'), findsOneWidget);
      expect(find.text('Page not found'), findsNothing);
      expect(
        coordinator.routeTable.bindings.map((b) => b.routeType),
        [CaseRoute, NotFoundRoute, ErrorRoute],
      );
    });
  });
}
