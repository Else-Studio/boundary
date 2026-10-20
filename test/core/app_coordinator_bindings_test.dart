// Test Plan:
//
// group: 'AppCoordinator route bindings'
//   - test: a route's binding creates its controller and enters it once
//   - test: an equal route keeps its controller
//   - test: a route with other params gets a new controller and the old one is disposed
//   - test: a modal gets its controller and page from its binding
//   - test: a page reads its controller from Provider
//   - test: with no state the fallback is built from the ErrorRoute binding
//   - test: the no-state fallback controller is created once
//   - test: the no-state fallback controller is disposed with the coordinator
//   - test: the no-state fallback controller is disposed when a base controller is created

import 'package:boundary/boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
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

class NoteModalRoute extends ConfigurationBase {
  static const String path = '/note';

  const NoteModalRoute() : super(isModal: true);

  @override
  String get pathTemplate => path;
}

/// Records what the coordinator does to it.
class CaseController extends Controller<void> {
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

class NoteController extends CaseController {}

class CasePage extends StatelessWidget {
  const CasePage({super.key});

  @override
  Widget build(BuildContext context) =>
      Text('case ${context.read<CaseController>().hashCode}');
}

class NotePage extends StatelessWidget {
  const NotePage({super.key});

  @override
  Widget build(BuildContext context) =>
      Text('note ${context.read<NoteController>().hashCode}');
}

void main() {
  group('AppCoordinator route bindings', () {
    late MockDependencyProvider provider;
    late BehaviorSubject<AuthState> authStream;
    late BehaviorSubject<ConfigurationBase> navStream;
    late AppCoordinator coordinator;

    // Every controller each binding factory has made, in order.
    late List<CaseController> caseControllers;
    late List<NoteController> noteControllers;
    late List<CaseController> errorControllers;

    RouteBinding<CaseRoute, CaseController> caseBinding() =>
        RouteBinding<CaseRoute, CaseController>(
          path: CaseRoute.path,
          parse: (p) => CaseRoute(int.parse(p['id']!)),
          controller: (_) {
            final controller = CaseController();
            caseControllers.add(controller);
            return controller;
          },
          page: const CasePage(),
        );

    RouteBinding<NoteModalRoute, NoteController> noteBinding() =>
        RouteBinding<NoteModalRoute, NoteController>(
          path: NoteModalRoute.path,
          parse: (_) => const NoteModalRoute(),
          controller: (_) {
            final controller = NoteController();
            noteControllers.add(controller);
            return controller;
          },
          page: const NotePage(),
        );

    setUp(() async {
      provider = MockDependencyProvider();
      await SutFactory.initTestBed(provider: provider);

      caseControllers = [];
      noteControllers = [];
      errorControllers = [];
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

    Future<void> pumpContent(WidgetTester tester, Widget content) =>
        tester.pumpWidget(MaterialApp(home: content));

    testWidgets("a route's binding creates its controller and enters it once",
        (tester) async {
      createCoordinator([caseBinding()]);

      await emit(tester, const CaseRoute(7));

      expect(caseControllers, hasLength(1));
      expect(caseControllers.single.entered, [const CaseRoute(7)]);
    });

    testWidgets('an equal route keeps its controller', (tester) async {
      createCoordinator([caseBinding()]);

      await emit(tester, const CaseRoute(7));
      await emit(tester, const CaseRoute(7));

      expect(caseControllers, hasLength(1));
      expect(caseControllers.single.disposeCount, 0);
      expect(caseControllers.single.entered, hasLength(1));
    });

    testWidgets(
        'a route with other params gets a new controller and the old one is disposed',
        (tester) async {
      createCoordinator([caseBinding()]);

      await emit(tester, const CaseRoute(7));
      await emit(tester, const CaseRoute(8));
      // The coordinator disposes the old controller after the next frame.
      tester.binding.scheduleFrame();
      await tester.pump();

      expect(caseControllers, hasLength(2));
      expect(caseControllers.first.disposeCount, 1);
      expect(caseControllers.last.entered, [const CaseRoute(8)]);
    });

    testWidgets('a modal gets its controller and page from its binding',
        (tester) async {
      createCoordinator([caseBinding(), noteBinding()]);

      await emit(tester, const CaseRoute(7));
      await emit(tester, const NoteModalRoute());

      expect(noteControllers, hasLength(1));
      expect(noteControllers.single.entered, [const NoteModalRoute()]);

      await pumpContent(tester, coordinator.getModalContentWidget()!);

      expect(tester.takeException(), isNull);
      expect(
        find.text('note ${noteControllers.single.hashCode}'),
        findsOneWidget,
      );
    });

    testWidgets('a page reads its controller from Provider', (tester) async {
      createCoordinator(<RouteBinding>[
        RouteBinding<CaseRoute, CaseController>(
          path: CaseRoute.path,
          parse: (p) => CaseRoute(int.parse(p['id']!)),
          controller: (_) {
            final controller = CaseController();
            caseControllers.add(controller);
            return controller;
          },
          page: const CasePage(),
        ),
      ]);

      await emit(tester, const CaseRoute(7));
      await pumpContent(tester, coordinator.getBaseContentWidget());

      expect(tester.takeException(), isNull);
      expect(
        find.text('case ${caseControllers.single.hashCode}'),
        findsOneWidget,
      );
    });

    testWidgets(
        'with no state the fallback is built from the ErrorRoute binding',
        (tester) async {
      createCoordinator(<RouteBinding>[
        caseBinding(),
        RouteBinding<ErrorRoute, CaseController>(
          path: ErrorRoute.path,
          parse: (p) => ErrorRoute(message: p['message'] ?? ''),
          controller: (_) {
            final controller = CaseController();
            errorControllers.add(controller);
            return controller;
          },
          page: const CasePage(),
        ),
      ]);
      await tester.runAsync(() => Future.delayed(Duration.zero));

      final content = coordinator.getBaseContentWidget();

      expect(errorControllers, hasLength(1));
      final entered = errorControllers.single.entered;
      expect(entered, hasLength(1));
      expect(entered.single, isA<ErrorRoute>());
      expect((entered.single as ErrorRoute).message, 'error.app.noState');

      await pumpContent(tester, content);

      expect(tester.takeException(), isNull);
      expect(
        find.text('case ${errorControllers.single.hashCode}'),
        findsOneWidget,
      );
    });

    RouteBinding<ErrorRoute, CaseController> errorBinding() =>
        RouteBinding<ErrorRoute, CaseController>(
          path: ErrorRoute.path,
          parse: (p) => ErrorRoute(message: p['message'] ?? ''),
          controller: (_) {
            final controller = CaseController();
            errorControllers.add(controller);
            return controller;
          },
          page: const CasePage(),
        );

    testWidgets('the no-state fallback controller is created once',
        (tester) async {
      createCoordinator(<RouteBinding>[caseBinding(), errorBinding()]);
      await tester.runAsync(() => Future.delayed(Duration.zero));

      final first = coordinator.getBaseContentWidget();
      final second = coordinator.getBaseContentWidget();

      expect(errorControllers, hasLength(1));
      await pumpContent(tester, first);
      expect(
        find.text('case ${errorControllers.single.hashCode}'),
        findsOneWidget,
      );
      await pumpContent(tester, second);
      expect(
        find.text('case ${errorControllers.single.hashCode}'),
        findsOneWidget,
      );
    });

    testWidgets(
        'the no-state fallback controller is disposed with the coordinator',
        (tester) async {
      createCoordinator(<RouteBinding>[caseBinding(), errorBinding()]);
      await tester.runAsync(() => Future.delayed(Duration.zero));
      coordinator.getBaseContentWidget();
      final fallback = errorControllers.single;
      expect(fallback.isDisposed, isFalse);

      coordinator.dispose();

      expect(fallback.isDisposed, isTrue);
    });

    testWidgets(
        'the no-state fallback controller is disposed when a base controller is created',
        (tester) async {
      createCoordinator(<RouteBinding>[caseBinding(), errorBinding()]);
      await tester.runAsync(() => Future.delayed(Duration.zero));
      coordinator.getBaseContentWidget();
      final fallback = errorControllers.single;

      await emit(tester, const CaseRoute(7));

      expect(coordinator.baseConfiguration, const CaseRoute(7));
      expect(fallback.isDisposed, isTrue);
    });
  });
}
