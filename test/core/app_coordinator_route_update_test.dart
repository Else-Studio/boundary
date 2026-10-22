// Test Plan:
//
// group: 'AppCoordinator route updates'
//   - test: a route-aware controller is updated, not recreated, when its route returns with other params
//   - test: an equal route does not update a route-aware controller
//   - test: a controller that is not route-aware is recreated when its route returns with other params
//   - test: a different route type recreates even a route-aware controller
//   - test: a route-aware modal controller is updated when its modal returns with other params
//   - test: updating a controller notifies listeners once

import 'package:boundary/boundary.dart';
import 'package:flutter/widgets.dart';
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

class TagRoute extends ConfigurationBase {
  static const String path = '/tags/:name';

  const TagRoute(this.name);

  final String name;

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => {'name': name};
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

/// Records what the coordinator does to it, and accepts route updates.
class AwareCaseController extends Controller<void>
    implements RouteUpdatable<CaseRoute> {
  final List<ConfigurationBase> entered = [];
  final List<CaseRoute> updated = [];
  int disposeCount = 0;

  @override
  void enter(ConfigurationBase route) {
    entered.add(route);
  }

  @override
  void update(CaseRoute route) {
    updated.add(route);
  }

  @override
  void handleAction(void action) {}

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}

/// Records what the coordinator does to it; it cannot be updated.
class PlainCaseController extends Controller<void> {
  final List<ConfigurationBase> entered = [];
  int disposeCount = 0;

  @override
  void enter(ConfigurationBase route) {
    entered.add(route);
  }

  @override
  void handleAction(void action) {}

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}

class AwareNoteController extends Controller<void>
    implements RouteUpdatable<NoteModalRoute> {
  final List<ConfigurationBase> entered = [];
  final List<NoteModalRoute> updated = [];
  int disposeCount = 0;

  @override
  void enter(ConfigurationBase route) {
    entered.add(route);
  }

  @override
  void update(NoteModalRoute route) {
    updated.add(route);
  }

  @override
  void handleAction(void action) {}

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}

class TagController extends Controller<void> {
  @override
  void handleAction(void action) {}
}

void main() {
  group('AppCoordinator route updates', () {
    late MockDependencyProvider provider;
    late BehaviorSubject<AuthState> authStream;
    late BehaviorSubject<ConfigurationBase> navStream;
    late AppCoordinator coordinator;

    // Every controller each binding factory has made, in order.
    late List<AwareCaseController> awareControllers;
    late List<PlainCaseController> plainControllers;
    late List<AwareNoteController> noteControllers;

    RouteBinding<CaseRoute, AwareCaseController> awareCaseBinding() =>
        RouteBinding<CaseRoute, AwareCaseController>(
          path: CaseRoute.path,
          parse: (p) => CaseRoute(int.parse(p['id']!)),
          controller: (_) {
            final controller = AwareCaseController();
            awareControllers.add(controller);
            return controller;
          },
          page: const SizedBox(),
        );

    RouteBinding<CaseRoute, PlainCaseController> plainCaseBinding() =>
        RouteBinding<CaseRoute, PlainCaseController>(
          path: CaseRoute.path,
          parse: (p) => CaseRoute(int.parse(p['id']!)),
          controller: (_) {
            final controller = PlainCaseController();
            plainControllers.add(controller);
            return controller;
          },
          page: const SizedBox(),
        );

    RouteBinding<TagRoute, TagController> tagBinding() =>
        RouteBinding<TagRoute, TagController>(
          path: TagRoute.path,
          parse: (p) => TagRoute(p['name']!),
          controller: (_) => TagController(),
          page: const SizedBox(),
        );

    RouteBinding<NoteModalRoute, AwareNoteController> noteBinding() =>
        RouteBinding<NoteModalRoute, AwareNoteController>(
          path: NoteModalRoute.path,
          parse: (p) => NoteModalRoute(int.parse(p['id']!)),
          controller: (_) {
            final controller = AwareNoteController();
            noteControllers.add(controller);
            return controller;
          },
          page: const SizedBox(),
        );

    setUp(() async {
      provider = MockDependencyProvider();
      await SutFactory.initTestBed(provider: provider);

      awareControllers = [];
      plainControllers = [];
      noteControllers = [];
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

    void createCoordinator(List<RouteBinding> routes) {
      when(provider.mockAppCoordinatorDelegate.routes).thenReturn(routes);
      coordinator = SutFactory.createAppCoordinator(provider: provider);
    }

    Future<void> emit(WidgetTester tester, ConfigurationBase route) async {
      navStream.add(route);
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
    }

    // The coordinator disposes an old controller after the next frame.
    Future<void> settleDisposals(WidgetTester tester) async {
      tester.binding.scheduleFrame();
      await tester.pump();
    }

    testWidgets('a route-aware controller is updated, not recreated',
        (tester) async {
      createCoordinator([awareCaseBinding()]);

      await emit(tester, const CaseRoute(7));
      await emit(tester, const CaseRoute(8));
      await settleDisposals(tester);

      expect(awareControllers, hasLength(1));
      expect(awareControllers.single.entered, [const CaseRoute(7)]);
      expect(awareControllers.single.updated, [const CaseRoute(8)]);
      expect(awareControllers.single.disposeCount, 0);
      expect(coordinator.baseConfiguration, const CaseRoute(8));
    });

    testWidgets('an equal route does not update a route-aware controller',
        (tester) async {
      createCoordinator([awareCaseBinding()]);

      await emit(tester, const CaseRoute(7));
      await emit(tester, const CaseRoute(7));

      expect(awareControllers, hasLength(1));
      expect(awareControllers.single.updated, isEmpty);
    });

    testWidgets(
        'a controller that is not route-aware is recreated when its route has other params',
        (tester) async {
      createCoordinator([plainCaseBinding()]);

      await emit(tester, const CaseRoute(7));
      await emit(tester, const CaseRoute(8));
      await settleDisposals(tester);

      expect(plainControllers, hasLength(2));
      expect(plainControllers.first.disposeCount, 1);
      expect(plainControllers.last.entered, [const CaseRoute(8)]);
    });

    testWidgets(
        'a different route type recreates even a route-aware controller',
        (tester) async {
      createCoordinator([awareCaseBinding(), tagBinding()]);

      await emit(tester, const CaseRoute(7));
      await emit(tester, const TagRoute('x'));
      await settleDisposals(tester);

      expect(awareControllers, hasLength(1));
      expect(awareControllers.single.updated, isEmpty);
      expect(awareControllers.single.disposeCount, 1);
    });

    testWidgets('a route-aware modal controller is updated, not recreated',
        (tester) async {
      createCoordinator([awareCaseBinding(), noteBinding()]);

      await emit(tester, const CaseRoute(7));
      await emit(tester, const NoteModalRoute(1));
      await emit(tester, const NoteModalRoute(2));
      await settleDisposals(tester);

      expect(noteControllers, hasLength(1));
      expect(noteControllers.single.updated, [const NoteModalRoute(2)]);
      expect(noteControllers.single.disposeCount, 0);
      expect(coordinator.modalConfiguration, const NoteModalRoute(2));
    });

    testWidgets('updating a controller notifies listeners once',
        (tester) async {
      createCoordinator([awareCaseBinding()]);
      var notifications = 0;
      coordinator.addListener(() => notifications++);

      await emit(tester, const CaseRoute(7));
      notifications = 0;
      await emit(tester, const CaseRoute(8));

      expect(awareControllers, hasLength(1));
      expect(awareControllers.single.updated, [const CaseRoute(8)]);
      expect(notifications, 1);
    });
  });
}
