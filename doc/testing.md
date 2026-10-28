# Testing

In a boundary app the logic lives in controllers, so controller tests carry most of the coverage. They are plain Dart tests: build the controller with test doubles, dispatch actions, and check its streams and the navigation it asked for. This page covers the test setup boundary recommends, the doubles in `package:boundary/testing.dart`, and how to test controllers, forms, leave guards and API clients.

The scenarios themselves come from your app: what a screen must do is your product's rules. This page shows the shape those tests take.

## What to test

| Layer | How |
|---|---|
| Controllers | Unit tests through actions and streams. This is where most tests go. |
| API clients | Unit tests against `FakeHttpBackend`: the request sent and the result or exception. |
| Services with state | Unit tests of their streams as their methods run. |
| Views | Optional. Views hold no logic, so a few smoke tests of the whole app are usually enough. Your app decides. |

Put tests in a `test/` tree that mirrors `lib/`.

## Setup

Quiet boundary's logs in tests with `test/flutter_test_config.dart`:

```dart
import 'dart:async';

import 'package:boundary/boundary.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  boundaryLogLevel = LogLevel.warning;
  await testMain();
}
```

`flutter_test` and `package:boundary/testing.dart` both export a `pumpEventQueue`. They do the same thing. Hide one of them in each test file:

```dart
import 'package:boundary/testing.dart';
import 'package:flutter_test/flutter_test.dart' hide pumpEventQueue;
```

## The three helpers

Keep test setup in three files under `test/helpers/`. Every controller test then needs very little arrangement, and a constructor change is fixed in one place.

### MockDependencyProvider

It holds every dependency a controller under test can ask for, stubbed so that everything succeeds. A test overrides one stub with `when(...)` for the case it checks. Use mockito mocks for your app's own services, and boundary's doubles (or the real class) for boundary's services:

```dart
class TestConfig implements AppConfig {
  @override
  String get baseUrl => 'http://test';

  @override
  Duration get debounceTime => const Duration(milliseconds: 20);
}

/// Every dependency a controller under test can ask for, stubbed for the
/// happy path. A test overrides one stub with when(...) for its own case.
class MockDependencyProvider {
  MockDependencyProvider() {
    _stubDefaults();
  }

  // The app's own services: mockito mocks.
  final cases = MockCaseRepository();
  final dialogs = MockDialogs();

  // Boundary's services: the doubles from testing.dart, or the real thing.
  final auth = FakeAuthService(
    initial: const Authenticated(AuthSession(subject: 'ada@example.com')),
    token: 'test-token',
  );
  final navigation = RecordingNavigationService(
    loginRoute: const LoginRoute(),
    homeRoute: const CasesRoute(),
  );
  final notices = NoticeService();
  late final errors = ErrorPolicy(notices, navigation);
  final config = TestConfig();

  void _stubDefaults() {
    when(cases.list()).thenAnswer((_) async => [ModelFactory.caseSummary()]);
    when(cases.get(any)).thenAnswer(
      (call) async => ModelFactory.caseSummary(
        id: call.positionalArguments.first as int,
      ),
    );
    when(cases.note(any)).thenAnswer((_) async => 'First visit.');
    when(cases.saveNote(any, any)).thenAnswer((_) async {});
    when(dialogs.confirmDiscard()).thenAnswer((_) async => false);
  }

  void dispose() {
    navigation.dispose();
    notices.dispose();
    auth.dispose();
  }
}
```

The mocks come from mockito. List the classes in `test/helpers/mocks.dart`, then run `dart run build_runner build --delete-conflicting-outputs`:

```dart
@GenerateMocks([CaseRepository, Dialogs])
void main() {}
```

### SutFactory

It is the only place tests build a class under test. Each `create` method takes the provider and passes its dependencies in:

```dart
abstract final class SutFactory {
  static CasesController createCasesController(MockDependencyProvider p) =>
      CasesController(p.cases, p.navigation);

  static CaseController createCaseController(MockDependencyProvider p) =>
      CaseController(
        p.cases,
        p.navigation,
        ControllerFactory(() => createNoteController(p)),
      );

  static NoteController createNoteController(MockDependencyProvider p) =>
      NoteController(p.cases, p.config, p.errors, p.navigation, p.dialogs);
}
```

### ModelFactory

It is the only place tests build models. Tests never write raw JSON or maps in `when` or `expect`. A test asks for a model and changes only the fields it cares about:

```dart
abstract final class ModelFactory {
  static CaseSummary caseSummary({int id = 1, String name = 'Ada'}) =>
      CaseSummary(id: id, name: name);
}
```

For dates, match the field: `DateTime.utc(...)` for an instant, a local `DateTime(y, m, d)` for a calendar date. See [api_client.md](api_client.md), "Models and dates".

## The doubles in testing.dart

`package:boundary/testing.dart` is for tests only. It does not depend on `flutter_test`.

| Double | What it is |
|---|---|
| `ControllerHarness(controller)` | Runs a controller's actions to the end and records its streams. |
| `pumpEventQueue()` | Lets queued microtasks and zero-delay timers run. |
| `FakeAuthService` | An `AuthService` whose state and token the test sets. |
| `RecordingNavigationService` | A real `NavigationService` that records every route it is asked for. |
| `FakeHttpBackend` | Canned HTTP responses for a real `HttpService`, and a record of the requests. |

### ControllerHarness

- `act(action)` dispatches the action, then waits with `pumpEventQueue()` until it has finished.
- `record(stream)` returns a list that collects every event from now on. For a `ValueStream`, the current value comes first.
- `dispose()` stops the recordings and disposes the controller.

```dart
test('a failed load shows a failure', () async {
  when(provider.cases.list()).thenThrow(NetworkException());
  final states = harness.record(harness.controller.cases);

  await harness.act(LoadCases());

  expect(states.last, isA<Failure<List<CaseSummary>>>());
});
```

### FakeAuthService

`FakeAuthService(initial: ..., token: ...)` starts in the given state. `signIn()` sets a token and emits `Authenticated`. `emit(state)` emits any state. `signOutCalls`, `initializeCalls` and `rejectedTokens` record what happened. A 401 report signs out with `expired` by default. Set `onUnauthorized` to return a new token instead.

```dart
final auth = FakeAuthService(initial: const SignedOut(SignedOutReason.noSession));
auth.signIn(session: const AuthSession(subject: 'ada@example.com'));
expect(auth.authState.value, isA<Authenticated>());
```

### RecordingNavigationService

`RecordingNavigationService(loginRoute: ..., homeRoute: ...)` is a real `NavigationService`, so leave guards and `navigateUp` behave as in the app. `requests` lists every route it was asked to show, in order. Leave out `routes` unless the test needs a binding's `transient` flag.

Nothing is shown in a test until you say so. Call `show(route)`, or `show(base, modal: route)`, before testing anything that depends on what is shown, such as `navigateUp`.

```dart
test('opening a case navigates to it', () async {
  await harness.act(OpenCase(2));

  expect(provider.navigation.requests, [const CaseRoute(2)]);
});
```

### FakeHttpBackend

`on(method, path, status: ..., body: ..., headers: ...)` sets the answer for a method and URL path. A non-string `body` is JSON-encoded. Several answers for the same key are served in order, and the last one repeats. A request with no answer gets a 404 problem. `requests` lists what was sent. Give `backend.client` to an `HttpService`. See "API clients" below for an example.

## Testing a controller

Build the provider and the harness in `setUp`, and dispose both in `tearDown`:

```dart
void main() {
  late MockDependencyProvider provider;
  late ControllerHarness<CasesAction, CasesController> harness;

  setUp(() {
    provider = MockDependencyProvider();
    harness = ControllerHarness(SutFactory.createCasesController(provider));
  });

  tearDown(() {
    harness.dispose();
    provider.dispose();
  });

  test('entering the route loads the cases', () async {
    final states = harness.record(harness.controller.cases);

    harness.controller.enter(const CasesRoute());
    await pumpEventQueue();

    expect(states.last, isA<Data<List<CaseSummary>>>());
    expect(states.last.dataOrNull!.single.name, 'Ada');
  });
}
```

- Drive the controller only as the app does: `enter`, `update`, and actions. Do not call its private helpers, and do not add public methods just for tests.
- Assert on its streams, on `provider.navigation.requests`, on notices, and on calls to your mocks with `verify`.
- A test of `RouteUpdatable` calls `enter` with one route, then `update` with another.
- A test of a filter or a search gives it at least one item that matches and one that does not. If every item matches, a filter that returns everything still passes.

## Waiting for async work

- After an action, wait with `harness.act`, or with `await pumpEventQueue()` after `dispatch` or `enter`. It waits until the queued work has run, without guessing a duration.
- Do not wait with `Future.delayed(Duration.zero)` or a few milliseconds. Those pass or fail by luck.
- To check a sequence of states, use `record` and compare the list. Or set up `expectLater(stream, emitsInOrder([...]))` before the action and await it after.
- Debounced work, like a form save, needs real time. Keep `debounceTime` short in the test config and wait a little longer than it. Avoid `fakeAsync`: `pumpEventQueue` waits on zero-delay timers, and those never fire under `fakeAsync` unless the test moves the clock.

## Forms

Edit a form the way a widget does: mark the control dirty, then set its value. A plain `control.value = x` leaves the control pristine, so `FormSession` does not save it. Keep a helper for this:

```dart
/// A user edit, the way a reactive_forms widget makes one: mark dirty, then
/// set the value. A plain `control.value = x` is not saved.
void userEdit(FormGroup form, String path, Object? value) {
  form.control(path)
    ..markAsDirty(emitEvent: false)
    ..value = value;
}
```

```dart
test('an edit is saved after the debounce', () async {
  final statuses = harness.record(harness.controller.status);

  userEdit(harness.controller.form, NoteFormKeys.note, 'Second visit.');
  await Future<void>.delayed(provider.config.debounceTime * 2);

  verify(provider.cases.saveNote(1, 'Second visit.')).called(1);
  expect(statuses, [
    SaveStatus.idle,
    SaveStatus.dirty,
    SaveStatus.saving,
    SaveStatus.saved,
  ]);
});
```

Things that catch people out:

- A form's `valueChanges` event arrives a moment after the edit. Right after `userEdit`, read `form.dirty` or `hasUnsavedChanges`, not the status. Wait with `pumpEventQueue()` before you check the status.
- A closed `BehaviorSubject` replays its last value before it is done, so `emitsDone` alone fails. Use `emitsInOrder([anything, emitsDone])`.
- To test a failed save, make the mock throw, then check the status is `error` and that a notice was shown.

## Leave guards

Tell the navigation service what is shown, make the form unsaved, navigate, and check that the dialog was asked and that nothing was requested:

```dart
test('leaving with an invalid note asks first, and Cancel stays', () async {
  provider.navigation.show(const CaseRoute(1));

  userEdit(harness.controller.form, NoteFormKeys.note, '');
  provider.navigation.navigateUp();
  await pumpEventQueue();

  verify(provider.dialogs.confirmDiscard()).called(1);
  expect(provider.navigation.requests, isEmpty);
});
```

## API clients

Build the client on a real `HttpService` with a `FakeHttpBackend`, set the answer, call the client, and check the result, the exception, or the request sent:

```dart
void main() {
  late FakeHttpBackend backend;
  late AuthApi api;

  setUp(() {
    initializeCoreMappers();
    backend = FakeHttpBackend();
    api = AuthApi(HttpService(FakeAuthService(), backend.client), TestConfig());
  });

  const credentials = LoginCredentials(email: 'ada@example.com', password: 'x');

  test('a refused password is CredentialsRejectedException', () async {
    backend.on('POST', '/api/auth/login', status: 401, body: {
      'title': 'Unauthorized',
      'status': 401,
      'reason': 'unauthorized',
    });

    await expectLater(
      api.login(credentials),
      throwsA(isA<CredentialsRejectedException>().having(
        (e) => e.problem?.extensions['reason'],
        'reason',
        'unauthorized',
      )),
    );
  });
}
```

`backend.requests` holds each `http.Request`, so a test can check its URL, headers and body.

## A smoke test of the whole app

One widget test can start the app with its real delegate, or a test delegate that registers fakes, and walk through sign-in. Call `SharedPreferences.setMockInitialValues({})` first if the app uses `SharedPreferencesCredentialStore`. Build the same `MaterialApp.router` as `main()`, then use `tester.pumpAndSettle()` after each tap. Dispose the coordinator at the end.
