import 'package:boundary/boundary.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sut_factory.dart';

void main() {
  setUp(() async {
    await SutFactory.initTestBed();
  });

  group('HttpProblem extensions', () {
    test('unknown members land in extensions', () {
      final problem = HttpProblemMapper.fromJson('{"reason":"unauthorized"}');

      expect(problem.extensions, {'reason': 'unauthorized'});
    });

    test('known members stay on the fields and unknown ones go to extensions',
        () {
      final problem = HttpProblemMapper.fromJson(
        '{"title":"Not allowed","status":403,"reason":"not_allowed"}',
      );

      expect(problem.title, 'Not allowed');
      expect(problem.status, 403);
      expect(problem.extensions, {'reason': 'not_allowed'});
    });

    test('a problem with only known members has empty extensions', () {
      final problem = HttpProblemMapper.fromJson(
        '{"title":"Not Found","status":404}',
      );

      expect(problem.extensions, <String, dynamic>{});
    });
  });
}
