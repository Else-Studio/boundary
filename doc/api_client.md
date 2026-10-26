# API clients

An API client turns calls like `list()` or `saveNote(id, text)` into HTTP requests, and turns the responses into models. Boundary's `BaseApiClient` does the shared work: it builds URIs, sends requests through `HttpService`, and maps every failure to a typed exception. This page covers writing a client, the exceptions it throws, problem+json bodies, `HttpService`, and dates.

## Writing a client

Define what your controllers need as an interface, and implement it with a client that extends `BaseApiClient`:

```dart
abstract interface class CaseRepository {
  Future<List<CaseSummary>> list();
  Future<CaseSummary> get(int id);
  Future<String> note(int caseId);
  Future<void> saveNote(int caseId, String note);
}

class CaseApi extends BaseApiClient implements CaseRepository {
  CaseApi(super.httpService, super.config);

  static const _casesPath = 'api/cases';

  @override
  Future<List<CaseSummary>> list({String? name, int? page}) {
    // Keys in alphabetical order, so tests can match the URI exactly.
    final query = <String, dynamic>{'name': name, 'page': page}
      ..removeWhere((_, value) => value == null);
    return performRequest(
      request: () => httpService.get(
        buildApiUri(_casesPath, queryParameters: query),
      ),
      parser: (body) => [
        for (final item in jsonDecode(body) as List)
          CaseSummary(id: item['id'] as int, name: item['name'] as String),
      ],
      resourceName: 'Cases',
    );
  }

  @override
  Future<void> saveNote(int caseId, String note) {
    return performRequest<void>(
      request: () => httpService.put(
        buildApiUri('$_casesPath/$caseId/note'),
        body: jsonEncode({'note': note}),
      ),
      parser: (_) {},
      resourceName: 'Note',
    );
  }

  // get, note ...
}
```

Register it under the interface. Its constructor takes `HttpService` and `AppConfig`, which the injector fills in, so register an `AppConfig` too:

```dart
injector.addInstance<AppConfig>(const DemoConfig());
injector.addSingleton<CaseRepository>(CaseApi.new);
```

Controllers depend on the interface, so tests can replace the client with a mock.

Conventions:

- Keep each path as a `static const` at the top of the client.
- Remove null query values yourself, as above. `buildApiUri` sends a null as the string `"null"`.
- Write query keys in alphabetical order. The URI is then the same every time, and a test can compare it exactly.
- Give each call a `resourceName`. It appears in error messages, such as "Case not found.".

## Building URIs

`buildApiUri(relativePath, queryParameters: ..., overrideBaseUrl: ...)` joins `AppConfig.baseUrl` and the path with exactly one slash between them. An `Iterable` value becomes a repeated key (`tag=a&tag=b`). Other values are turned into strings. `overrideBaseUrl` replaces the base URL for one call.

## Sending requests

| Method | Use it for |
|---|---|
| `performRequest(request:, parser:, resourceName:)` | A normal call. `parser` gets the body as a string. |
| `performMultipartRequest(...)` | A file upload, with `httpService.postMultipart`. Same parser shape. |
| `performRawRequest(request:, parser:, resourceName:)` | A call that needs the whole `http.Response`, such as headers or bytes. `parser` gets the response, and a `FormatException` it throws is not mapped. |

With `performRequest`, an empty body is fine when the result type is nullable or `void`. For any other type, an empty body throws `DataParsingException`. Bad JSON, or any `FormatException` from the parser, also throws `DataParsingException`.

Each `HttpService` method takes `requireAuth`, which defaults to true. Pass `requireAuth: false` for calls that must not send a token, such as login. [auth.md](auth.md) explains what a 401 means in each case.

## Exceptions

Every failure becomes an `ApiException` subclass. Each has a `message` and, when the server sent a problem+json body, a `problem`.

| Cause | Exception | Default message |
|---|---|---|
| Timeout, no connection, DNS failure | `NetworkException` | Could not connect. Please check your network connection. |
| 400 | `InvalidInputException` | The problem's `detail`, or "Invalid input provided for {resource}." Its `validationProblem` holds the violations. |
| 401 on a call that needed a token | `SessionTerminatedException` | The problem's `detail`, or "Your session has expired. Please log in again." |
| 401 on a call that needed no token | `CredentialsRejectedException` | The problem's `detail`, or "The sign-in details were not accepted." |
| 403 | `ForbiddenException` | The problem's `detail`, or "You do not have permission to access this resource." |
| 404 | `ResourceNotFoundException` | "{resource} not found." |
| 429, after retries | `RateLimitExceededException` | You are making too many requests. Please wait a moment and try again. |
| 5xx | `ServerUnavailableException` | The server is currently unavailable. Please try again later. |
| Any other status | `ApiException` | The problem's `detail`, or "Failed to load {resource}: Status {code}" |
| Bad JSON, or an empty body for a non-nullable type | `DataParsingException` | Failed to parse API response: … |

Catch the ones you want to show inline in the controller. Let the rest reach `onError`. See [errors.md](errors.md).

## Problem bodies

Boundary expects error bodies in problem+json form (RFC 9457). `BaseApiClient` decodes them into an `HttpProblem` with `type`, `title`, `status`, `detail`, `instance` and `details`. A body with `violations` decodes into `HttpValidationProblem`, whose `violations` each have a `field`, an `in` and a `message`.

Members the model does not name are kept in `problem.extensions`. A server that sends a machine-readable reason can be read like this:

```dart
on ApiException catch (e) {
  if (e.problem?.extensions['reason'] == 'not_allowed') {
    // ...
  }
}
```

Call `initializeCoreMappers()` once in `main()`, before any request, so these models can be decoded.

`FormSession` puts a failed save's violations on its form fields. See [forms.md](forms.md).

## HttpService

`HttpService` is the transport under every client. The coordinator registers it. You call its `get`, `post`, `put`, `patch`, `delete` and `postMultipart` from your clients, and it:

- adds `Accept: application/json`, and `Content-Type: application/json; charset=UTF-8` when there is a body, unless you pass your own;
- adds the bearer token when `requireAuth` is true, and handles a 401 as [auth.md](auth.md) describes;
- times out after 60 seconds, and does not retry a timeout or a connection error;
- retries a 429 up to two more times. It waits as long as the `Retry-After` header says, or 2 and then 4 seconds;
- throws an `HttpException` for any other non-2xx status, which `BaseApiClient` maps to the table above.

## Models and dates

Boundary's own models use `dart_mappable`. Your models can use it too, or anything else that turns JSON into Dart objects.

APIs send two kinds of date, and both become `DateTime` in Dart. Keep them apart:

| On the wire | In Dart | In test data |
|---|---|---|
| An instant: `2025-03-01T09:30:00Z` | `DateTime`, decoded as is | `DateTime.utc(2025, 3, 1, 9, 30)` |
| A calendar date: `2025-03-01` | A local `DateTime(2025, 3, 1)`, through a per-field hook | `DateTime(2025, 3, 1)`, not `DateTime.utc` |
| A clock time: `09:00` | A `String` | `'09:00'` |

A calendar date must decode to local midnight. Decoded as UTC, it can show as the day before in some time zones. With `dart_mappable`, put a hook on each calendar-date field: `@MappableField(hook: LocalDateHook())`. Do not register a global `DateTime` mapper, which would change every instant as well.

```dart
class LocalDateHook extends MappingHook {
  const LocalDateHook();

  static final _format = DateFormat('yyyy-MM-dd');

  @override
  Object? beforeDecode(Object? value) {
    if (value is! String) return value;
    final parsed = DateTime.parse(value);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  @override
  Object? beforeEncode(Object? value) =>
      value is DateTime ? _format.format(value) : value;
}
```

## Testing a client

Test a client against `FakeHttpBackend` from `package:boundary/testing.dart`. It serves canned responses to a real `HttpService` and records the requests. See [testing.md](testing.md), "API clients".
