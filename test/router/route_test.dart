import 'package:boundary/boundary.dart';
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

class CaseCopyRoute extends ConfigurationBase {
  static const String path = '/cases/:id';

  const CaseCopyRoute(this.id);

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

class HomeRoute extends ConfigurationBase {
  static const String path = '/';

  const HomeRoute();

  @override
  String get pathTemplate => path;
}

class BrokenRoute extends ConfigurationBase {
  static const String path = '/cases/:id';

  const BrokenRoute();

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => const {};
}

void main() {
  group('route equality', () {
    test('two routes of the same type and URI are equal and hash alike', () {
      expect(CaseRoute(7), equals(CaseRoute(7)));
      expect(CaseRoute(7).hashCode, CaseRoute(7).hashCode);
      expect({CaseRoute(7), CaseRoute(7)}, hasLength(1));
    });

    test('routes with different URIs are not equal', () {
      expect(CaseRoute(7), isNot(equals(CaseRoute(8))));
    });

    test('routes of different types with the same URI are not equal', () {
      expect(CaseRoute(7).uri.toString(), '/cases/7');
      expect(CaseCopyRoute(7).uri.toString(), '/cases/7');
      expect(CaseRoute(7), isNot(equals(CaseCopyRoute(7))));
    });
  });

  group('route URI', () {
    test('a path value fills its segment', () {
      expect(CaseRoute(7).uri.toString(), '/cases/7');
    });

    test('params that match no segment become query parameters', () {
      expect(
        CaseRoute(7, tab: 'notes').uri.toString(),
        '/cases/7?tab=notes',
      );
    });

    test('a template without segments gives its own path', () {
      expect(HomeRoute().uri.toString(), '/');
    });

    test('path values are percent-encoded', () {
      expect(TagRoute('a b/c').uri.toString(), '/tags/a%20b%2Fc');
    });

    test('a segment with no value throws ArgumentError', () {
      expect(() => BrokenRoute().uri, throwsArgumentError);
    });
  });

  group('framework routes', () {
    test('error routes compare their problem as well as their URI', () {
      expect(
        ErrorRoute(message: 'm', problem: HttpProblem(title: 'A')),
        equals(
          ErrorRoute(message: 'm', problem: HttpProblem(title: 'A')),
        ),
      );
      expect(
        ErrorRoute(message: 'm', problem: HttpProblem(title: 'A')),
        isNot(
          equals(
            ErrorRoute(message: 'm', problem: HttpProblem(title: 'B')),
          ),
        ),
      );
    });

    test('not-found routes compare their original URL', () {
      expect(NotFoundRoute('/a'), equals(NotFoundRoute('/a')));
      expect(NotFoundRoute('/a'), isNot(equals(NotFoundRoute('/b'))));
    });

    test('an error route puts its message and flag in the query', () {
      expect(
        ErrorRoute(message: 'x y').uri.toString(),
        '/error?message=x+y&isSessionTermination=false',
      );
    });
  });
}
