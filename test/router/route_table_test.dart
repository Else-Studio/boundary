import 'package:boundary/boundary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class CaseRoute extends ConfigurationBase {
  static const String path = '/cases/:id';

  const CaseRoute(this.id, {this.tab});

  final int id;
  final String? tab;

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => {'id': '$id', if (tab != null) 'tab': tab!};
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

class CaseNewRoute extends ConfigurationBase {
  static const String path = '/cases/new';

  const CaseNewRoute();

  @override
  String get pathTemplate => path;
}

class HomeRoute extends ConfigurationBase {
  static const String path = '/';

  const HomeRoute();

  @override
  String get pathTemplate => path;
}

class SectionItemRoute extends ConfigurationBase {
  static const String path = '/:section/:item';

  const SectionItemRoute(this.section, this.item);

  final String section;
  final String item;

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => {'section': section, 'item': item};
}

class MisboundRoute extends ConfigurationBase {
  static const String path = '/misbound';

  const MisboundRoute();

  @override
  String get pathTemplate => path;
}

class FakeController extends Controller<String> {
  @override
  void handleAction(String action) {}
}

final caseBinding = RouteBinding<CaseRoute, FakeController>(
  path: CaseRoute.path,
  parse: (p) => CaseRoute(int.parse(p['id']!), tab: p['tab']),
  controller: (_) => FakeController(),
  page: const SizedBox(),
);

final anotherCaseBinding = RouteBinding<CaseRoute, FakeController>(
  path: CaseRoute.path,
  parse: (p) => CaseRoute(int.parse(p['id']!)),
  controller: (_) => FakeController(),
  page: const SizedBox(),
);

final tagBinding = RouteBinding<TagRoute, FakeController>(
  path: TagRoute.path,
  parse: (p) => TagRoute(p['name']!),
  controller: (_) => FakeController(),
  page: const SizedBox(),
);

final caseNewBinding = RouteBinding<CaseNewRoute, FakeController>(
  path: CaseNewRoute.path,
  parse: (_) => const CaseNewRoute(),
  controller: (_) => FakeController(),
  page: const SizedBox(),
);

final homeBinding = RouteBinding<HomeRoute, FakeController>(
  path: HomeRoute.path,
  parse: (_) => const HomeRoute(),
  controller: (_) => FakeController(),
  page: const SizedBox(),
);

final sectionItemBinding = RouteBinding<SectionItemRoute, FakeController>(
  path: SectionItemRoute.path,
  parse: (p) => SectionItemRoute(p['section']!, p['item']!),
  controller: (_) => FakeController(),
  page: const SizedBox(),
);

// Given another route's path by mistake.
final misboundBinding = RouteBinding<MisboundRoute, FakeController>(
  path: '/elsewhere',
  parse: (_) => const MisboundRoute(),
  controller: (_) => FakeController(),
  page: const SizedBox(),
);

void main() {
  group('RouteTable parsing', () {
    late RouteTable table;

    setUp(() {
      table = RouteTable([caseBinding, tagBinding, homeBinding]);
    });

    test('a URL with a path value and a query value gives the route', () {
      final route = table.parse(Uri.parse('/cases/7?tab=notes'));

      expect(route, isA<CaseRoute>());
      expect((route as CaseRoute).id, 7);
      expect(route.tab, 'notes');
    });

    test('a trailing slash still matches', () {
      final route = table.parse(Uri.parse('/cases/7/'));

      expect(route, isA<CaseRoute>());
      expect((route as CaseRoute).id, 7);
      expect(route.tab, isNull);
    });

    test('the root URL gives the root route', () {
      expect(table.parse(Uri.parse('/')), isA<HomeRoute>());
    });

    test('path values are decoded before they reach parse', () {
      final route = table.parse(Uri.parse('/tags/a%20b%2Fc'));

      expect(route, isA<TagRoute>());
      expect((route as TagRoute).name, 'a b/c');
    });

    test('a parse that throws gives a not-found route', () {
      final route = table.parse(Uri.parse('/cases/abc'));

      expect(route, isA<NotFoundRoute>());
      expect((route as NotFoundRoute).originalUrl, '/cases/abc');
    });

    test('a URL no binding matches gives a not-found route', () {
      final route = table.parse(Uri.parse('/nowhere?x=1'));

      expect(route, isA<NotFoundRoute>());
      expect((route as NotFoundRoute).originalUrl, '/nowhere?x=1');
    });

    test('the first matching binding in order wins', () {
      final newFirst = RouteTable([caseNewBinding, caseBinding]);

      expect(newFirst.parse(Uri.parse('/cases/new')), isA<CaseNewRoute>());
    });

    test('a later binding is not tried after the first match fails to parse',
        () {
      final caseFirst = RouteTable([caseBinding, caseNewBinding]);

      final route = caseFirst.parse(Uri.parse('/cases/new'));

      expect(route, isA<NotFoundRoute>());
      expect((route as NotFoundRoute).originalUrl, '/cases/new');
    });

    test('list order wins over path length', () {
      final longFirst = RouteTable([sectionItemBinding, caseNewBinding]);
      final shortFirst = RouteTable([caseNewBinding, sectionItemBinding]);

      expect(
        longFirst.parse(Uri.parse('/cases/new')),
        isA<SectionItemRoute>(),
      );
      expect(shortFirst.parse(Uri.parse('/cases/new')), isA<CaseNewRoute>());
    });

    test('a path value wins over a query value of the same name', () {
      final route = table.parse(Uri.parse('/cases/7?id=9'));

      expect(route, isA<CaseRoute>());
      expect((route as CaseRoute).id, 7);
    });
  });

  group('RouteTable bindings', () {
    test('two bindings for one route type throw ArgumentError', () {
      expect(
        () => RouteTable([caseBinding, anotherCaseBinding]),
        throwsArgumentError,
      );
    });

    test('bindingFor returns the binding of the route type', () {
      final table = RouteTable([caseBinding]);

      expect(table.bindingFor(const CaseRoute(1)), same(caseBinding));
    });

    test('bindingFor throws StateError for a route type with no binding', () {
      final table = RouteTable([caseBinding]);

      expect(() => table.bindingFor(const TagRoute('x')), throwsStateError);
    });

    test('bindingFor throws StateError when the binding has another path', () {
      final table = RouteTable([misboundBinding]);

      expect(
        () => table.bindingFor(const MisboundRoute()),
        throwsStateError,
      );
    });

    test(
        'bindings lists the given bindings first, in order, and cannot be modified',
        () {
      final table = RouteTable([caseBinding, tagBinding]);

      expect(table.bindings, [
        caseBinding,
        tagBinding,
        defaultErrorRouteBinding,
        defaultNotFoundRouteBinding,
      ]);
      expect(() => table.bindings.add(homeBinding), throwsUnsupportedError);
    });

    test('the default bindings come after the app bindings, error first', () {
      final table = RouteTable([caseBinding]);

      expect(
        table.bindings.map((b) => b.routeType),
        [CaseRoute, ErrorRoute, NotFoundRoute],
      );
      expect(table.bindings[1], same(defaultErrorRouteBinding));
      expect(table.bindings[2], same(defaultNotFoundRouteBinding));
    });
  });

  group('AppRouteInformationParser', () {
    late AppRouteInformationParser parser;

    setUp(() {
      parser = AppRouteInformationParser(RouteTable([caseBinding]));
    });

    test('parsing route information gives the route from the table', () async {
      final route = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/cases/7')),
      );

      expect(route, isA<CaseRoute>());
      expect((route as CaseRoute).id, 7);
    });

    test('restoring route information gives the route URI', () {
      final info = parser.restoreRouteInformation(
        const CaseRoute(7, tab: 'notes'),
      );

      expect(info.uri.toString(), '/cases/7?tab=notes');
    });
  });
}
