// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'error_models.dart';

class HttpProblemMapper extends ClassMapperBase<HttpProblem> {
  HttpProblemMapper._();

  static HttpProblemMapper? _instance;
  static HttpProblemMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = HttpProblemMapper._());
      HttpValidationProblemMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'HttpProblem';

  static String? _$type(HttpProblem v) => v.type;
  static const Field<HttpProblem, String> _f$type = Field(
    'type',
    _$type,
    opt: true,
  );
  static String? _$title(HttpProblem v) => v.title;
  static const Field<HttpProblem, String> _f$title = Field(
    'title',
    _$title,
    opt: true,
  );
  static int? _$status(HttpProblem v) => v.status;
  static const Field<HttpProblem, int> _f$status = Field(
    'status',
    _$status,
    opt: true,
  );
  static String? _$detail(HttpProblem v) => v.detail;
  static const Field<HttpProblem, String> _f$detail = Field(
    'detail',
    _$detail,
    opt: true,
  );
  static String? _$instance(HttpProblem v) => v.instance;
  static const Field<HttpProblem, String> _f$instance = Field(
    'instance',
    _$instance,
    opt: true,
  );
  static List<String>? _$details(HttpProblem v) => v.details;
  static const Field<HttpProblem, List<String>> _f$details = Field(
    'details',
    _$details,
    opt: true,
  );
  static Map<String, dynamic> _$extensions(HttpProblem v) => v.extensions;
  static const Field<HttpProblem, Map<String, dynamic>> _f$extensions = Field(
    'extensions',
    _$extensions,
    opt: true,
    def: const <String, dynamic>{},
  );

  @override
  final MappableFields<HttpProblem> fields = const {
    #type: _f$type,
    #title: _f$title,
    #status: _f$status,
    #detail: _f$detail,
    #instance: _f$instance,
    #details: _f$details,
    #extensions: _f$extensions,
  };

  @override
  final MappingHook hook = const UnmappedPropertiesHook('extensions');
  static HttpProblem _instantiate(DecodingData data) {
    return HttpProblem(
      type: data.dec(_f$type),
      title: data.dec(_f$title),
      status: data.dec(_f$status),
      detail: data.dec(_f$detail),
      instance: data.dec(_f$instance),
      details: data.dec(_f$details),
      extensions: data.dec(_f$extensions),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static HttpProblem fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<HttpProblem>(map);
  }

  static HttpProblem fromJson(String json) {
    return ensureInitialized().decodeJson<HttpProblem>(json);
  }
}

mixin HttpProblemMappable {
  String toJson() {
    return HttpProblemMapper.ensureInitialized().encodeJson<HttpProblem>(
      this as HttpProblem,
    );
  }

  Map<String, dynamic> toMap() {
    return HttpProblemMapper.ensureInitialized().encodeMap<HttpProblem>(
      this as HttpProblem,
    );
  }

  HttpProblemCopyWith<HttpProblem, HttpProblem, HttpProblem> get copyWith =>
      _HttpProblemCopyWithImpl<HttpProblem, HttpProblem>(
        this as HttpProblem,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return HttpProblemMapper.ensureInitialized().stringifyValue(
      this as HttpProblem,
    );
  }

  @override
  bool operator ==(Object other) {
    return HttpProblemMapper.ensureInitialized().equalsValue(
      this as HttpProblem,
      other,
    );
  }

  @override
  int get hashCode {
    return HttpProblemMapper.ensureInitialized().hashValue(this as HttpProblem);
  }
}

extension HttpProblemValueCopy<$R, $Out>
    on ObjectCopyWith<$R, HttpProblem, $Out> {
  HttpProblemCopyWith<$R, HttpProblem, $Out> get $asHttpProblem =>
      $base.as((v, t, t2) => _HttpProblemCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class HttpProblemCopyWith<$R, $In extends HttpProblem, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>?>? get details;
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>
  get extensions;
  $R call({
    String? type,
    String? title,
    int? status,
    String? detail,
    String? instance,
    List<String>? details,
    Map<String, dynamic>? extensions,
  });
  HttpProblemCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _HttpProblemCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, HttpProblem, $Out>
    implements HttpProblemCopyWith<$R, HttpProblem, $Out> {
  _HttpProblemCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<HttpProblem> $mapper =
      HttpProblemMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>?>? get details =>
      $value.details != null
      ? ListCopyWith(
          $value.details!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(details: v),
        )
      : null;
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>?>
  get extensions => MapCopyWith(
    $value.extensions,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(extensions: v),
  );
  @override
  $R call({
    Object? type = $none,
    Object? title = $none,
    Object? status = $none,
    Object? detail = $none,
    Object? instance = $none,
    Object? details = $none,
    Map<String, dynamic>? extensions,
  }) => $apply(
    FieldCopyWithData({
      if (type != $none) #type: type,
      if (title != $none) #title: title,
      if (status != $none) #status: status,
      if (detail != $none) #detail: detail,
      if (instance != $none) #instance: instance,
      if (details != $none) #details: details,
      if (extensions != null) #extensions: extensions,
    }),
  );
  @override
  HttpProblem $make(CopyWithData data) => HttpProblem(
    type: data.get(#type, or: $value.type),
    title: data.get(#title, or: $value.title),
    status: data.get(#status, or: $value.status),
    detail: data.get(#detail, or: $value.detail),
    instance: data.get(#instance, or: $value.instance),
    details: data.get(#details, or: $value.details),
    extensions: data.get(#extensions, or: $value.extensions),
  );

  @override
  HttpProblemCopyWith<$R2, HttpProblem, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _HttpProblemCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ViolationMapper extends ClassMapperBase<Violation> {
  ViolationMapper._();

  static ViolationMapper? _instance;
  static ViolationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ViolationMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'Violation';

  static String? _$field(Violation v) => v.field;
  static const Field<Violation, String> _f$field = Field(
    'field',
    _$field,
    opt: true,
  );
  static String? _$inField(Violation v) => v.inField;
  static const Field<Violation, String> _f$inField = Field(
    'inField',
    _$inField,
    key: r'in',
    opt: true,
  );
  static String? _$message(Violation v) => v.message;
  static const Field<Violation, String> _f$message = Field(
    'message',
    _$message,
    opt: true,
  );

  @override
  final MappableFields<Violation> fields = const {
    #field: _f$field,
    #inField: _f$inField,
    #message: _f$message,
  };

  static Violation _instantiate(DecodingData data) {
    return Violation(
      field: data.dec(_f$field),
      inField: data.dec(_f$inField),
      message: data.dec(_f$message),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Violation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Violation>(map);
  }

  static Violation fromJson(String json) {
    return ensureInitialized().decodeJson<Violation>(json);
  }
}

mixin ViolationMappable {
  String toJson() {
    return ViolationMapper.ensureInitialized().encodeJson<Violation>(
      this as Violation,
    );
  }

  Map<String, dynamic> toMap() {
    return ViolationMapper.ensureInitialized().encodeMap<Violation>(
      this as Violation,
    );
  }

  ViolationCopyWith<Violation, Violation, Violation> get copyWith =>
      _ViolationCopyWithImpl<Violation, Violation>(
        this as Violation,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ViolationMapper.ensureInitialized().stringifyValue(
      this as Violation,
    );
  }

  @override
  bool operator ==(Object other) {
    return ViolationMapper.ensureInitialized().equalsValue(
      this as Violation,
      other,
    );
  }

  @override
  int get hashCode {
    return ViolationMapper.ensureInitialized().hashValue(this as Violation);
  }
}

extension ViolationValueCopy<$R, $Out> on ObjectCopyWith<$R, Violation, $Out> {
  ViolationCopyWith<$R, Violation, $Out> get $asViolation =>
      $base.as((v, t, t2) => _ViolationCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ViolationCopyWith<$R, $In extends Violation, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? field, String? inField, String? message});
  ViolationCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ViolationCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Violation, $Out>
    implements ViolationCopyWith<$R, Violation, $Out> {
  _ViolationCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Violation> $mapper =
      ViolationMapper.ensureInitialized();
  @override
  $R call({
    Object? field = $none,
    Object? inField = $none,
    Object? message = $none,
  }) => $apply(
    FieldCopyWithData({
      if (field != $none) #field: field,
      if (inField != $none) #inField: inField,
      if (message != $none) #message: message,
    }),
  );
  @override
  Violation $make(CopyWithData data) => Violation(
    field: data.get(#field, or: $value.field),
    inField: data.get(#inField, or: $value.inField),
    message: data.get(#message, or: $value.message),
  );

  @override
  ViolationCopyWith<$R2, Violation, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ViolationCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class HttpValidationProblemMapper
    extends SubClassMapperBase<HttpValidationProblem> {
  HttpValidationProblemMapper._();

  static HttpValidationProblemMapper? _instance;
  static HttpValidationProblemMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = HttpValidationProblemMapper._());
      HttpProblemMapper.ensureInitialized().addSubMapper(_instance!);
      ViolationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'HttpValidationProblem';

  static String? _$type(HttpValidationProblem v) => v.type;
  static const Field<HttpValidationProblem, String> _f$type = Field(
    'type',
    _$type,
    opt: true,
  );
  static String? _$title(HttpValidationProblem v) => v.title;
  static const Field<HttpValidationProblem, String> _f$title = Field(
    'title',
    _$title,
    opt: true,
  );
  static int? _$status(HttpValidationProblem v) => v.status;
  static const Field<HttpValidationProblem, int> _f$status = Field(
    'status',
    _$status,
    opt: true,
  );
  static String? _$detail(HttpValidationProblem v) => v.detail;
  static const Field<HttpValidationProblem, String> _f$detail = Field(
    'detail',
    _$detail,
    opt: true,
  );
  static List<String>? _$details(HttpValidationProblem v) => v.details;
  static const Field<HttpValidationProblem, List<String>> _f$details = Field(
    'details',
    _$details,
    opt: true,
  );
  static String? _$instance(HttpValidationProblem v) => v.instance;
  static const Field<HttpValidationProblem, String> _f$instance = Field(
    'instance',
    _$instance,
    opt: true,
  );
  static Map<String, dynamic> _$extensions(HttpValidationProblem v) =>
      v.extensions;
  static const Field<HttpValidationProblem, Map<String, dynamic>>
  _f$extensions = Field(
    'extensions',
    _$extensions,
    opt: true,
    def: const <String, dynamic>{},
  );
  static List<Violation> _$violations(HttpValidationProblem v) => v.violations;
  static const Field<HttpValidationProblem, List<Violation>> _f$violations =
      Field('violations', _$violations, opt: true, def: const []);

  @override
  final MappableFields<HttpValidationProblem> fields = const {
    #type: _f$type,
    #title: _f$title,
    #status: _f$status,
    #detail: _f$detail,
    #details: _f$details,
    #instance: _f$instance,
    #extensions: _f$extensions,
    #violations: _f$violations,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = MappableClass.useAsDefault;
  @override
  late final ClassMapperBase superMapper =
      HttpProblemMapper.ensureInitialized();

  @override
  final MappingHook superHook = const UnmappedPropertiesHook('extensions');

  static HttpValidationProblem _instantiate(DecodingData data) {
    return HttpValidationProblem(
      type: data.dec(_f$type),
      title: data.dec(_f$title),
      status: data.dec(_f$status),
      detail: data.dec(_f$detail),
      details: data.dec(_f$details),
      instance: data.dec(_f$instance),
      extensions: data.dec(_f$extensions),
      violations: data.dec(_f$violations),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static HttpValidationProblem fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<HttpValidationProblem>(map);
  }

  static HttpValidationProblem fromJson(String json) {
    return ensureInitialized().decodeJson<HttpValidationProblem>(json);
  }
}

mixin HttpValidationProblemMappable {
  String toJson() {
    return HttpValidationProblemMapper.ensureInitialized()
        .encodeJson<HttpValidationProblem>(this as HttpValidationProblem);
  }

  Map<String, dynamic> toMap() {
    return HttpValidationProblemMapper.ensureInitialized()
        .encodeMap<HttpValidationProblem>(this as HttpValidationProblem);
  }

  HttpValidationProblemCopyWith<
    HttpValidationProblem,
    HttpValidationProblem,
    HttpValidationProblem
  >
  get copyWith =>
      _HttpValidationProblemCopyWithImpl<
        HttpValidationProblem,
        HttpValidationProblem
      >(this as HttpValidationProblem, $identity, $identity);
  @override
  String toString() {
    return HttpValidationProblemMapper.ensureInitialized().stringifyValue(
      this as HttpValidationProblem,
    );
  }

  @override
  bool operator ==(Object other) {
    return HttpValidationProblemMapper.ensureInitialized().equalsValue(
      this as HttpValidationProblem,
      other,
    );
  }

  @override
  int get hashCode {
    return HttpValidationProblemMapper.ensureInitialized().hashValue(
      this as HttpValidationProblem,
    );
  }
}

extension HttpValidationProblemValueCopy<$R, $Out>
    on ObjectCopyWith<$R, HttpValidationProblem, $Out> {
  HttpValidationProblemCopyWith<$R, HttpValidationProblem, $Out>
  get $asHttpValidationProblem => $base.as(
    (v, t, t2) => _HttpValidationProblemCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class HttpValidationProblemCopyWith<
  $R,
  $In extends HttpValidationProblem,
  $Out
>
    implements HttpProblemCopyWith<$R, $In, $Out> {
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get details;
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>
  get extensions;
  ListCopyWith<$R, Violation, ViolationCopyWith<$R, Violation, Violation>>
  get violations;
  @override
  $R call({
    String? type,
    String? title,
    int? status,
    String? detail,
    List<String>? details,
    String? instance,
    Map<String, dynamic>? extensions,
    List<Violation>? violations,
  });
  HttpValidationProblemCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _HttpValidationProblemCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, HttpValidationProblem, $Out>
    implements HttpValidationProblemCopyWith<$R, HttpValidationProblem, $Out> {
  _HttpValidationProblemCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<HttpValidationProblem> $mapper =
      HttpValidationProblemMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get details =>
      $value.details != null
      ? ListCopyWith(
          $value.details!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(details: v),
        )
      : null;
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>
  get extensions => MapCopyWith(
    $value.extensions,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(extensions: v),
  );
  @override
  ListCopyWith<$R, Violation, ViolationCopyWith<$R, Violation, Violation>>
  get violations => ListCopyWith(
    $value.violations,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(violations: v),
  );
  @override
  $R call({
    Object? type = $none,
    Object? title = $none,
    Object? status = $none,
    Object? detail = $none,
    Object? details = $none,
    Object? instance = $none,
    Map<String, dynamic>? extensions,
    List<Violation>? violations,
  }) => $apply(
    FieldCopyWithData({
      if (type != $none) #type: type,
      if (title != $none) #title: title,
      if (status != $none) #status: status,
      if (detail != $none) #detail: detail,
      if (details != $none) #details: details,
      if (instance != $none) #instance: instance,
      if (extensions != null) #extensions: extensions,
      if (violations != null) #violations: violations,
    }),
  );
  @override
  HttpValidationProblem $make(CopyWithData data) => HttpValidationProblem(
    type: data.get(#type, or: $value.type),
    title: data.get(#title, or: $value.title),
    status: data.get(#status, or: $value.status),
    detail: data.get(#detail, or: $value.detail),
    details: data.get(#details, or: $value.details),
    instance: data.get(#instance, or: $value.instance),
    extensions: data.get(#extensions, or: $value.extensions),
    violations: data.get(#violations, or: $value.violations),
  );

  @override
  HttpValidationProblemCopyWith<$R2, HttpValidationProblem, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _HttpValidationProblemCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

