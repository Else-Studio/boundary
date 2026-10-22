import 'package:dart_mappable/dart_mappable.dart';

part 'error_models.mapper.dart';

/// Initializes the core mappers used in the framework.
/// This should be called once at application startup in main().
void initializeCoreMappers() {
  HttpProblemMapper.ensureInitialized();
  HttpValidationProblemMapper.ensureInitialized();
  ViolationMapper.ensureInitialized();
}

@MappableClass(discriminatorKey: 'type')
class HttpProblem with HttpProblemMappable {
  final String? type;
  final String? title;
  final int? status;
  final String? detail;
  final String? instance;
  final List<String>? details;

  /// Members the problem JSON carried that are not named fields above.
  final Map<String, dynamic> extensions;

  const HttpProblem({
    this.type,
    this.title,
    this.status,
    this.detail,
    this.instance,
    this.details,
    this.extensions = const <String, dynamic>{},
  });
}

@MappableClass()
class Violation with ViolationMappable {
  final String? field;
  final String? inField;
  final String? message;

  const Violation({
    this.field,
    @MappableField(key: 'in') this.inField,
    this.message,
  });
}

@MappableClass(discriminatorValue: MappableClass.useAsDefault)
class HttpValidationProblem extends HttpProblem
    with HttpValidationProblemMappable {
  final List<Violation> violations;

  const HttpValidationProblem({
    super.type,
    super.title,
    super.status,
    super.detail,
    super.details,
    super.instance,
    super.extensions,
    this.violations = const [],
  });
}
