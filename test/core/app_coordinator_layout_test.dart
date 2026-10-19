// Test Plan:
//
// group: 'AppCoordinator layouts'
//   - test: a layout wraps the page and provides its controller
//   - test: routes that share a layout keep its controller
//   - test: a route without the layout disposes it
//   - test: a different layout replaces the current one
//   - test: a layout controller is not kept alive after its routes are left
//   - test: a modal keeps the base layout and ignores its own
//   - test: the layout controller is created before the route controller
//   - test: disposing the coordinator disposes the layout controller
//   - test: a replaced base controller is disposed

import 'package:boundary/boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/mock_dependency_provider.dart';
import '../helpers/model_factory.dart';
import '../helpers/sut_factory.dart';

class CasesRoute extends ConfigurationBase {
  static const String path = '/cases';

  const CasesRoute();

  @override
  String get pathTemplate => path;
}

class NotesRoute extends ConfigurationBase {
  static const String path = '/notes';

  const NotesRoute();

  @override
  String get pathTemplate => path;
}

class AdminRoute extends ConfigurationBase {
  static const String path = '/admin';

  const AdminRoute();

  @override
  String get pathTemplate => path;
}

class PublicRoute extends ConfigurationBase {
  static const String path = '/about';

  const PublicRoute();

  @override
  String get pathTemplate => path;
}

class NoteModalRoute extends ConfigurationBase {
  static const String path = '/note';

  const NoteModalRoute() : super(isModal: true);

  @override
  String get pathTemplate => path;
}

/// Counts how often the coordinator disposes it.
class LayoutController extends Controller<void> {
  int disposeCount = 0;

  @override
  void handleAction(void action) {}

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}

/// A route controller that counts disposals.
class RoutePageController extends Controller<void> {
  int disposeCount = 0;

  @override
  void handleAction(void action) {}

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}

/// Shows the hash code of the layout controller it reads from Provider above
/// its child.
class ShellProbe extends StatelessWidget {
  const ShellProbe({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('shell ${context.read<LayoutController>().hashCode}'),
        child,
      ],
    );
  }
}

// What each factory has made, in order. Reset in setUp.
final List<LayoutController> shellControllers = [];
final List<LayoutController> adminShellControllers = [];
final List<RoutePageController> casesControllers = [];
final List<String> creationOrder = [];

// Each layout is declared once and reused by every binding that shares it.
final LayoutBinding<LayoutController> shell = LayoutBinding<LayoutController>(
  controller: (_) {
    final controller = LayoutController();
    shellControllers.add(controller);
    creationOrder.add('layout');
    return controller;
  },
  builder: (child) => ShellProbe(key: const ValueKey('shell'), child: child),
);

final LayoutBinding<LayoutController> adminShell =
    LayoutBinding<LayoutController>(
  controller: (_) {
    final controller = LayoutController();
    adminShellControllers.add(controller);
    return controller;
  },
  builder: (child) =>
      ShellProbe(key: const ValueKey('admin-shell'), child: child),
);

void main() {
  group('AppCoordinator layouts', () {
    late MockDependencyProvider provider;
    late BehaviorSubject<AsyncResult<User>> authStream;
    late BehaviorSubject<ConfigurationBase> navStream;
    late AppCoordinator coordinator;

    final bindings = <RouteBinding>[
      RouteBinding<CasesRoute, RoutePageController>(
        path: CasesRoute.path,
        parse: (_) => const CasesRoute(),
        controller: (_) {
          final controller = RoutePageController();
          casesControllers.add(controller);
          creationOrder.add('cases');
          return controller;
        },
        page: const Text('cases'),
        layout: shell,
      ),
      RouteBinding<NotesRoute, RoutePageController>(
        path: NotesRoute.path,
        parse: (_) => const NotesRoute(),
        controller: (_) => RoutePageController(),
        page: const Text('notes'),
        layout: shell,
      ),
      RouteBinding<AdminRoute, RoutePageController>(
        path: AdminRoute.path,
        parse: (_) => const AdminRoute(),
        controller: (_) => RoutePageController(),
        page: const Text('admin'),
        layout: adminShell,
      ),
      RouteBinding<PublicRoute, RoutePageController>(
        path: PublicRoute.path,
        parse: (_) => const PublicRoute(),
        controller: (_) => RoutePageController(),
        page: const Text('about'),
        access: RouteAccess.public,
      ),
      RouteBinding<NoteModalRoute, RoutePageController>(
        path: NoteModalRoute.path,
        parse: (_) => const NoteModalRoute(),
        controller: (_) => RoutePageController(),
        page: const Text('note'),
        // A modal ignores its layout.
        layout: adminShell,
      ),
    ];

    setUp(() async {
      shellControllers.clear();
      adminShellControllers.clear();
      casesControllers.clear();
      creationOrder.clear();

      provider = MockDependencyProvider();
      await SutFactory.initTestBed(provider: provider);

      authStream = BehaviorSubject.seeded(Data(ModelFactory.createUser()));
      navStream = BehaviorSubject();
      when(provider.mockAuthService.userStream)
          .thenAnswer((_) => authStream.stream);
      when(provider.mockAuthService.isLoading).thenReturn(false);
      when(provider.mockNavigationService.routeRequestStream)
          .thenAnswer((_) => navStream.stream);
      when(provider.mockAppCoordinatorDelegate.routes).thenReturn(bindings);

      coordinator = SutFactory.createAppCoordinator(provider: provider);
    });

    tearDown(() {
      authStream.close();
      navStream.close();
    });

    // Emits the route, lets the coordinator reconcile, and runs a frame so
    // the controllers it disposes after the frame are disposed.
    Future<void> emit(WidgetTester tester, ConfigurationBase route) async {
      navStream.add(route);
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
      tester.binding.scheduleFrame();
      await tester.pump();
    }

    Future<void> pumpContent(WidgetTester tester, Widget content) =>
        tester.pumpWidget(MaterialApp(home: content));

    testWidgets('a layout wraps the page and provides its controller',
        (tester) async {
      await emit(tester, const CasesRoute());

      await pumpContent(tester, coordinator.getBaseContentWidget());

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('shell')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('shell')),
          matching: find.text('cases'),
        ),
        findsOneWidget,
      );
      expect(shellControllers, hasLength(1));
      expect(coordinator.layoutController, same(shellControllers.single));
      expect(
        find.text('shell ${shellControllers.single.hashCode}'),
        findsOneWidget,
      );
    });

    testWidgets('routes that share a layout keep its controller',
        (tester) async {
      await emit(tester, const CasesRoute());
      await emit(tester, const NotesRoute());

      expect(shellControllers, hasLength(1));
      expect(shellControllers.single.disposeCount, 0);
      expect(coordinator.layoutController, same(shellControllers.single));
    });

    testWidgets('a route without the layout disposes it', (tester) async {
      await emit(tester, const CasesRoute());
      await emit(tester, const PublicRoute());

      expect(shellControllers, hasLength(1));
      expect(shellControllers.single.disposeCount, 1);
      expect(coordinator.layoutController, isNull);

      await pumpContent(tester, coordinator.getBaseContentWidget());

      expect(tester.takeException(), isNull);
      expect(find.text('about'), findsOneWidget);
      expect(find.byType(ShellProbe), findsNothing);
    });

    testWidgets('a different layout replaces the current one', (tester) async {
      await emit(tester, const CasesRoute());
      await emit(tester, const AdminRoute());

      expect(shellControllers, hasLength(1));
      expect(shellControllers.single.disposeCount, 1);
      expect(adminShellControllers, hasLength(1));
      expect(coordinator.layoutController, same(adminShellControllers.single));

      await pumpContent(tester, coordinator.getBaseContentWidget());

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('admin-shell')), findsOneWidget);
      expect(find.byKey(const ValueKey('shell')), findsNothing);
    });

    testWidgets(
        'a layout controller is not kept alive after its routes are left',
        (tester) async {
      await emit(tester, const CasesRoute());
      await emit(tester, const PublicRoute());
      await emit(tester, const CasesRoute());

      expect(shellControllers, hasLength(2));
      expect(shellControllers.first.disposeCount, 1);
      expect(shellControllers.last.disposeCount, 0);
      expect(coordinator.layoutController, same(shellControllers.last));
    });

    testWidgets('a modal keeps the base layout and ignores its own',
        (tester) async {
      await emit(tester, const CasesRoute());
      await emit(tester, const NoteModalRoute());

      expect(shellControllers, hasLength(1));
      expect(shellControllers.single.disposeCount, 0);
      expect(coordinator.layoutController, same(shellControllers.single));
      expect(adminShellControllers, isEmpty);

      await pumpContent(tester, coordinator.getModalContentWidget()!);

      expect(tester.takeException(), isNull);
      expect(find.text('note'), findsOneWidget);
      expect(find.byType(ShellProbe), findsNothing);
    });

    testWidgets('the layout controller is created before the route controller',
        (tester) async {
      await emit(tester, const CasesRoute());

      expect(creationOrder, ['layout', 'cases']);
    });

    testWidgets('disposing the coordinator disposes the layout controller',
        (tester) async {
      await emit(tester, const CasesRoute());

      coordinator.dispose();

      expect(shellControllers, hasLength(1));
      expect(shellControllers.single.disposeCount, 1);
    });

    testWidgets('a replaced base controller is disposed', (tester) async {
      await emit(tester, const CasesRoute());
      await emit(tester, const NotesRoute());

      expect(casesControllers, hasLength(1));
      expect(casesControllers.single.disposeCount, 1);
    });
  });
}
