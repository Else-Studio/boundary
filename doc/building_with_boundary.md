# Building an app with boundary

Read this page before you write a controller, a route, a form or a test in an app built on boundary. It gives the rules every feature follows and points to the guide for each task. The guides in this folder explain each part in depth. [`GETTING_STARTED.md`](../GETTING_STARTED.md) sets up a new app from nothing.

## How a boundary app works

A boundary app has three layers:

- **Services** talk to the outside world: the API, storage, auth. They hold no screen state.
- **Controllers** hold the logic and the state of one screen or one part of a screen. They take actions in and put state out on streams.
- **Views** are widgets. They draw what the controller's streams say, and they send the user's intents to the controller as actions.

Navigation is data. Each destination is a route class, such as `CaseRoute(12)`, with a path like `/cases/:id`. A `RouteBinding` ties the route to its controller and its page. You ask for a route with `NavigationService.navigateTo(route)`. The `AppCoordinator` combines that request with the auth state, applies access rules and guards, and decides what to show. It then creates the controller, calls `enter(route)` on it, and builds the page with the controller provided above it.

```
navigateTo(CaseRoute(12))  ──►  AppCoordinator  ◄──  AuthService.authState
                                    │  access, guards
                                    ▼
                           RouteBinding for CaseRoute
                     creates CaseController, calls enter(route)
                                    ▼
                    CasePage reads it with context.read<CaseController>()
                                    │
             user taps  ──►  controller.dispatch(NextCase())
                                    ▼
                handleAction  ──►  services  ──►  emit(stream, value)  ──►  page rebuilds
```

## The rules

These rules keep logic testable and screens predictable. Follow them unless a guide says otherwise for a specific case.

### 1. Views only draw and dispatch

A view reads its controller with `context.read<C>()`, listens to the controller's streams, and calls `controller.dispatch(action)` for every user intent. It does not compute, filter or decide. It does not build API request objects. It never writes a controller field or changes a form array by hand.

If a view needs a derived value, such as "can save" or a sorted list, the controller computes it and puts it on a stream. [views.md](views.md) covers splitting a page into widgets, lists, dialogs and styling.

### 2. Every intent is an action

Each controller has a sealed action type, and `handleAction` is its one entry point for work:

```dart
sealed class CasesAction {}

final class LoadCases extends CasesAction {}

final class OpenCase extends CasesAction {
  OpenCase(this.id);
  final int id;
}
```

A controller's public surface is its streams, its read-only getters (such as a `FormGroup` for the form widgets), `dispatch`, and the lifecycle methods `enter`, `update` and `dispose`. Do not add public methods that do work, like `save()` or `search(text)`. A view must not await the controller either. It dispatches and then reacts to the streams.

```dart
// Wrong: a public method, awaited by the view.
onPressed: () async => await controller.save(),

// Right: an action. The page shows progress from a stream.
onPressed: () => controller.dispatch(SaveCase()),
```

Actions run concurrently. A second action starts while a first async one is still running. When a late result could overwrite newer state, check that it still applies before you emit it. See [controllers.md](controllers.md).

### 3. The coordinator creates route controllers

Do not construct a route's controller or call its `enter` yourself, except in tests. The binding's `controller` closure gets a new one from the injector, and the coordinator calls `enter(route)` once, before the page is built. Start the first load from `enter`, usually by dispatching an action.

When the same route type comes back with other params, for example `CaseRoute(1)` to `CaseRoute(2)`, the controller is disposed and a new one is created. If the screen should stay and only reload, implement `RouteUpdatable<R>` and handle `update(route)`.

### 4. Navigate with route objects

Use `NavigationService`: `navigateTo(route)`, `navigateUp()`, `navigateBack()`, `dismissModal()`. Do not use `Navigator.push` or URL strings. `Navigator.pop` is only for closing a dialog you opened with `showDialog`.

Do not navigate after signing in or out. The coordinator watches the auth state. After sign-in it leaves the login route by itself, and after sign-out it shows the login route.

### 5. Own what you create, and emit safely

Register every subject, form, subscription, timer, child controller and `FormSession` with `own(...)`. `dispose()` then releases them in reverse order. Put values on your subjects with `emit(subject, value)`. Unlike `add`, it does nothing after dispose, so a late async result cannot throw.

```dart
late final _cases = own(
  BehaviorSubject<AsyncResult<List<CaseSummary>>>.seeded(const Loading()),
);
```

When you pass `Loading`, `Empty` or `Failure` to `emit`, give the type argument: `emit(_cases, const Loading<List<CaseSummary>>())`. Without it Dart infers `Loading<dynamic>`. That compiles, but the subject throws a type error at runtime.

### 6. Split state by how often it changes

Expose one stream per concern, so a widget rebuilds only for the data it uses. A small page can have a single state stream. When parts change at different rates, split them: for example the case details (rarely changes), the save status (changes on every edit), and a busy flag. Do not bundle data sets into one object when they load or change independently.

Loaded data uses `AsyncResult<T>`: `Loading`, `Data(value)`, `Failure(error)` or `Empty`. Views show it with `AsyncResultBuilder`.

### 7. Decide what each error means

An error thrown in `handleAction` goes to the controller's `onError`. By default it is only logged. Handle errors in one of three ways:

- **Inline:** catch the exception you expect in `handleAction` and put a message on a stream. For example, a refused sign-in is shown under the button.
- **A notice:** override `onError` and call `ErrorPolicy.handle(error, stackTrace)`. The policy shows a SnackBar notice, or does nothing for an expired session, because the user is already being signed out.
- **A failed load:** catch it and emit `Failure(error)`, so the page can show a retry.

A child controller's errors are not passed to its parent. See [errors.md](errors.md).

### 8. Children talk to parents through streams

A part of a page with its own logic gets its own child controller, owned by the parent through `adopt` or a `slot`. The child exposes output streams. The parent subscribes with `listenTo(child.events, handler)`. Do not give a child a callback field that calls into its parent. See [sub_controllers.md](sub_controllers.md).

### 9. Forms that save themselves use FormSession

An auto-saving form is a reactive_forms `FormGroup` inside a `FormSession`. The session debounces edits, saves once at a time, reports a `SaveStatus`, takes server updates without overwriting the user's edits, and maps server validation errors onto fields. Add a `FormLeaveGuard` so the user cannot lose unsaved changes by navigating away. Declare form control names as constants:

```dart
abstract final class NoteFormKeys {
  static const note = 'note';
}
```

See [forms.md](forms.md).

### 10. Test logic through the controller

Because logic lives in controllers, controller tests carry the coverage. Build the controller under test in one factory, give it mocks for your own services and boundary's test doubles for boundary's services, dispatch actions, and assert on its streams and on the navigation it requested. See [testing.md](testing.md).

## Adding a feature

A new screen touches these places. The guides show each one in full.

1. **The route class**: a `static const path`, `pathTemplate`, `params` for the path values, and `parent` if back should go somewhere. See [routing.md](routing.md).
2. **The controller**: its action type, its streams, `enter`, `handleAction`, and `onError` if it wants notices. See [controllers.md](controllers.md).
3. **The page**: a `StatelessWidget` that reads the controller and dispatches actions. Inside a layout, the page does not build its own `Scaffold`; the layout provides it.
4. **The binding**: add a `RouteBinding` to your delegate's `routes`, with `controller: (i) => i.get<MyController>()`, its `access` and its `layout`. Bindings match in list order, so put a fixed path like `/cases/new` before `/cases/:id`.
5. **Dependencies**: in `registerDependencies`, register the controller with `injector.add(MyController.new)`, and any new service or API client. Give constructor tear-offs: the injector fills their parameters by type. Register a child controller the same way, plus its factory with `addControllerFactory`. See [architecture.md](architecture.md), "Dependency injection".
6. **Tests**: add the controller to your `SutFactory`, stub its services in your `MockDependencyProvider`, and test its actions.

Keep a small feature in one file with its route, actions, controller and page. Split a large one into a controller file, a page file, and section widgets.

## Where to find what

| I want to… | Read |
|---|---|
| Start a new app | [GETTING_STARTED.md](../GETTING_STARTED.md) |
| Understand the layers and the controller lifecycle | [architecture.md](architecture.md) |
| Write a controller: actions, streams, `own`, `emit`, `enter`, `update` | [controllers.md](controllers.md) |
| Add a page, put an id in the URL, set who may see it | [routing.md](routing.md) |
| Share an app bar or menu between pages | [routing.md](routing.md), "Layouts" |
| Open a page as a modal, or make back go to a parent page | [routing.md](routing.md) |
| Send users somewhere first, for example by role | [routing.md](routing.md), "Guards" |
| Sign users in and out, store the token | [auth.md](auth.md) |
| Call the API and map its errors | [api_client.md](api_client.md) |
| Show an error inline, as a notice, or as a page | [errors.md](errors.md) |
| Give part of a page its own controller, or switch a detail pane by id | [sub_controllers.md](sub_controllers.md) |
| Split a page into widgets, show a list, open a dialog, style a view | [views.md](views.md) |
| Build an auto-saving form, or warn before leaving | [forms.md](forms.md) |
| Keep a form's list of rows in step with the server | [forms.md](forms.md), "Lists of rows" |
| Test a controller or an API client | [testing.md](testing.md) |

## Entry libraries

Import only these. Never import a file under `package:boundary/` that is not one of them.

| Import | What it gives you |
|---|---|
| `package:boundary/boundary.dart` | Controllers, routing, the coordinator, auth, HTTP, errors and notices, `AsyncResult`, logging. |
| `package:boundary/forms.dart` | `FormSession`, `SaveStatus`, `FormLeaveGuard`. |
| `package:boundary/testing.dart` | Test doubles and `ControllerHarness`. Use it in tests only. |
| `package:boundary/formatters.dart` | `AppFormatters` for dates, numbers and currency. |
| `package:boundary/oauth.dart` | A deprecated, web-only OAuth service. New apps use `StoredTokenAuthService`. |

## Tell your app's agents about this page

An agent working in your app's folder does not read boundary's files on its own. Add this to your app's `AGENTS.md`, with the path that fits your layout:

```markdown
## Framework

This app is built on boundary (`../boundary`). Before you write a controller, route, form or test, read `../boundary/doc/building_with_boundary.md` and follow its rules. The guides it links to explain each part.
```
