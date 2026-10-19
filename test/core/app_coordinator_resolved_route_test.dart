// Test Plan:
//
// group: 'AppCoordinator resolved routes'
//   - test: the coordinator reports the route it shows after a redirect, not the request
//   - test: an update is reported
//   - test: a modal opening and closing is reported
//   - test: the report comes before listeners are notified

import 'package:boundary/boundary.dart';
import 'package:flutter/widgets.dart' hide RouteAware;
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/mock_dependency_provider.dart';
import '../helpers/mocks.mocks.dart';
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

class NoteModalRoute extends ConfigurationBase {
  static const String path = '/notes/:id';

  const NoteModalRoute(this.id) : super(isModal: true);

  final int id;

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => {'id': '$id'};
}

class FakeProtectedRoute extends ConfigurationBase {
  const FakeProtectedRoute();

  @override
  String get pathTemplate => '/protected';
}

class FakeLoginRoute extends ConfigurationBase {
  const FakeLoginRoute();

  @override
  String get pathTemplate => '/login';
}

class AwareCaseController extends Controller<void>
    implements RouteAware<CaseRoute> {
  @override
  void update(CaseRoute route) {}

  @override
  void handleAction(void action) {}
}

class NoteController extends Controller<void> {
  @override
  void handleAction(void action) {}
}

class LoginController extends Controller<void> {
  @override
  void handleAction(void action) {}
}

void main() {
  group('AppCoordinator resolved routes', () {
    late MockDependencyProvider provider;
    late BehaviorSubject<AsyncResult<User>> authStream;
    late BehaviorSubject<ConfigurationBase> navStream;
    late AppCoordinator coordinator;

    final routes = <RouteBinding>[
      RouteBinding<CaseRoute, AwareCaseController>(
        path: CaseRoute.path,
        parse: (p) => CaseRoute(int.parse(p['id']!)),
        controller: (_) => AwareCaseController(),
        page: const SizedBox(),
      ),
      RouteBinding<NoteModalRoute, NoteController>(
        path: NoteModalRoute.path,
        parse: (p) => NoteModalRoute(int.parse(p['id']!)),
        controller: (_) => NoteController(),
        page: const SizedBox(),
      ),
      RouteBinding<FakeProtectedRoute, LoginController>(
        path: '/protected',
        parse: (_) => const FakeProtectedRoute(),
        controller: (_) => LoginController(),
        page: const SizedBox(),
        access: RouteAccess.protected,
      ),
      RouteBinding<FakeLoginRoute, LoginController>(
        path: '/login',
        parse: (_) => const FakeLoginRoute(),
        controller: (_) => LoginController(),
        page: const SizedBox(),
        access: RouteAccess.guestOnly,
      ),
    ];

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
      when(provider.mockAppCoordinatorDelegate.routes).thenReturn(routes);
    });

    tearDown(() {
      authStream.close();
      navStream.close();
    });

    MockNavigationService navigation() => provider.mockNavigationService;

    Future<void> emit(WidgetTester tester, ConfigurationBase route) async {
      navStream.add(route);
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
    }

    testWidgets(
        'the coordinator reports the route it shows after a redirect, not the request',
        (tester) async {
      authStream.add(const Failure(NoSessionStored()));
      when(provider.mockAppCoordinatorDelegate.getLoginRoute())
          .thenReturn(const FakeLoginRoute());
      coordinator = SutFactory.createAppCoordinator(provider: provider);

      await emit(tester, const FakeProtectedRoute());

      verify(navigation()
              .onRouteResolved(base: const FakeLoginRoute(), modal: null))
          .called(1);
      verifyNever(navigation().onRouteResolved(
          base: const FakeProtectedRoute(), modal: anyNamed('modal')));
    });

    testWidgets('an update is reported', (tester) async {
      coordinator = SutFactory.createAppCoordinator(provider: provider);

      await emit(tester, const CaseRoute(7));
      await emit(tester, const CaseRoute(8));

      verifyInOrder([
        navigation().onRouteResolved(base: const CaseRoute(7), modal: null),
        navigation().onRouteResolved(base: const CaseRoute(8), modal: null),
      ]);
    });

    testWidgets('a modal opening and closing is reported', (tester) async {
      coordinator = SutFactory.createAppCoordinator(provider: provider);

      await emit(tester, const CaseRoute(7));
      await emit(tester, const NoteModalRoute(1));
      await emit(tester, const CaseRoute(7));

      verifyInOrder([
        navigation().onRouteResolved(base: const CaseRoute(7), modal: null),
        navigation().onRouteResolved(
            base: const CaseRoute(7), modal: const NoteModalRoute(1)),
        navigation().onRouteResolved(base: const CaseRoute(7), modal: null),
      ]);
      verifyNever(navigation()
          .onRouteResolved(base: const CaseRoute(8), modal: anyNamed('modal')));
    });

    testWidgets('the report comes before listeners are notified',
        (tester) async {
      final order = <String>[];
      when(navigation().onRouteResolved(
        base: anyNamed('base'),
        modal: anyNamed('modal'),
      )).thenAnswer((_) => order.add('reported'));
      coordinator = SutFactory.createAppCoordinator(provider: provider);
      coordinator.addListener(() => order.add('notified'));

      await emit(tester, const CaseRoute(7));

      expect(order, ['reported', 'notified']);
    });
  });
}
