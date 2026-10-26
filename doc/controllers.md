# Controllers

A controller holds the logic and state of one screen, one layout, or one part of a screen. It takes actions in, calls services, and puts its state on streams for the view. This page shows how to write one. For where controllers fit in the app, see [architecture.md](architecture.md).

## A complete controller

```dart
sealed class CasesAction {}

final class LoadCases extends CasesAction {}

final class OpenCase extends CasesAction {
  OpenCase(this.id);
  final int id;
}

class CasesController extends Controller<CasesAction> {
  CasesController(this._cases, this._navigation);

  final CaseRepository _cases;
  final NavigationService _navigation;

  late final _list = own(
    BehaviorSubject<AsyncResult<List<CaseSummary>>>.seeded(const Loading()),
  );

  ValueStream<AsyncResult<List<CaseSummary>>> get cases => _list.stream;

  @override
  void enter(CasesRoute route) => dispatch(LoadCases());

  @override
  Future<void> handleAction(CasesAction action) async {
    switch (action) {
      case LoadCases():
        emit(_list, const Loading<List<CaseSummary>>());
        try {
          emit(_list, Data(await _cases.list()));
        } catch (e, s) {
          emit(_list, Failure<List<CaseSummary>>(e, stackTrace: s));
        }
      case OpenCase(:final id):
        _navigation.navigateTo(CaseRoute(id));
    }
  }
}
```

Register it in `registerDependencies` with `injector.add(CasesController.new)`. The injector fills its constructor's parameters by type. Its binding asks for a new one, and the coordinator calls `enter` once:

```dart
RouteBinding<CasesRoute, CasesController>(
  path: CasesRoute.path,
  parse: (_) => const CasesRoute(),
  controller: (i) => i.get<CasesController>(),
  page: const CasesPage(),
  layout: shell,
),
```

The page reads it and dispatches:

```dart
class CasesPage extends StatelessWidget {
  const CasesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<CasesController>();
    return AsyncResultBuilder<List<CaseSummary>>(
      stream: controller.cases,
      data: (context, cases) => ListView(
        children: [
          for (final item in cases)
            ListTile(
              title: Text(item.name),
              onTap: () => controller.dispatch(OpenCase(item.id)),
            ),
        ],
      ),
      failure: (context, failure) => Center(
        child: TextButton(
          onPressed: () => controller.dispatch(LoadCases()),
          child: const Text('Try again'),
        ),
      ),
    );
  }
}
```

## Actions

Declare a sealed class for the controller's actions, with one `final class` per intent. A `switch` over a sealed type is checked for completeness, so adding an action shows you every place that must handle it. For a controller with a few actions that carry no data, an `enum` is fine:

```dart
enum ShellAction { signOut }
```

`handleAction` returns `FutureOr<void>`, so it can be `async`. Each `dispatch(action)` runs `handleAction` once. Dispatching to a disposed controller logs a warning and does nothing.

### Actions run concurrently

Actions are not queued. A second action starts while a first async one is still waiting. This keeps the screen responsive, but a slow result can arrive after a newer one. When that matters, remember what the newest request was, and drop a result that no longer applies:

```dart
case LoadCase(:final id):
  _id = id;
  try {
    final found = await _cases.get(id);
    // Actions run concurrently. Drop a result for a case we left.
    if (_id == id) emit(_detail, Data(found));
  } catch (e, s) {
    if (_id == id) {
      emit(_detail, Failure<CaseSummary>(e, stackTrace: s));
    }
  }
```

To stop a double submit, keep a busy flag on a stream, disable the button while it is true, and return early from the action when it is already set.

## State on streams

Keep each piece of state in a `BehaviorSubject` that the controller owns, and expose it as a `ValueStream`. A `ValueStream` has a current `value`, so a view can build its first frame without waiting for an event.

```dart
late final _busy = own(BehaviorSubject<bool>.seeded(false));

ValueStream<bool> get busy => _busy.stream;
```

Use `AsyncResult<T>` for anything that loads: `Loading()`, `Data(value)`, `Failure(error, stackTrace: s)`, or `Empty()` when there is nothing to show yet. `dataOrNull` gives the data or null.

Put values on subjects with `emit(subject, value)`, not `subject.add(value)`. `emit` does nothing when the controller is disposed or the subject is closed. An async action that finishes after the user has left the page therefore cannot throw.

**Give the type argument when you pass `Loading`, `Empty` or `Failure` to `emit`.** `emit(_list, const Loading())` compiles, but Dart infers `Loading<dynamic>`, and the subject throws a type error at runtime. Write `emit(_list, const Loading<List<CaseSummary>>())`. `Data(value)` takes its type from the value, so it needs none.

Split state by how often it changes, as [building_with_boundary.md](building_with_boundary.md) rule 6 explains.

In a view, show an `AsyncResult` stream with `AsyncResultBuilder`. It draws a spinner for `Loading`, nothing for `Empty`, and "Something went wrong." for `Failure` unless you pass your own builders. Show any other stream with a `StreamBuilder` that starts from the current value:

```dart
StreamBuilder<bool>(
  stream: controller.busy,
  initialData: controller.busy.value,
  builder: (context, busy) => FilledButton(
    onPressed: busy.data! ? null : () => controller.dispatch(SignIn()),
    child: const Text('Sign in'),
  ),
),
```

## Owning resources

`own(resource)` registers a resource to be released when the controller is disposed, and returns it. Resources are released in reverse order of registration. An error while releasing one goes to `onError`, and the rest are still released.

| You own | Released with |
|---|---|
| `StreamController`, including rxdart subjects | `close()` |
| `StreamSubscription` | `cancel()` |
| `CompositeSubscription` | `dispose()` |
| `Timer` | `cancel()` |
| A reactive_forms `FormGroup`, `FormControl` or `FormArray` | `dispose()` |
| A child `Controller` | `dispose()` |
| A `ChangeNotifier`, such as a `TextEditingController` or `FocusNode` | `dispose()` |
| Anything implementing `Disposable`, such as a `FormSession` or the result of `addLeaveGuard` | `dispose()` |

Any other type throws an `ArgumentError`. If you call `own` after the controller is disposed, the resource is released at once.

`late final x = own(...)` is a short way to declare an owned field. A `late` field is created the first time it is read. That is fine for state the view reads. Anything that must exist from the start, such as a subscription or a leave guard registration, belongs in the constructor body:

```dart
NoteController(/* ... */ NavigationService navigation, Dialogs dialogs) {
  own(navigation.addLeaveGuard(
    FormLeaveGuard(_session, confirm: dialogs.confirmDiscard),
  ));
}
```

## Listening to other streams

To react to a service's stream, or to a child controller's events, use `listenTo(stream, handler)`. The subscription is owned, so it ends with the controller. An error event, or a throw from the handler, sync or async, goes to `onError`, and the subscription keeps running.

A layout controller can follow the shown route this way, to highlight the current menu item:

```dart
class MenuController extends Controller<MenuAction> {
  MenuController(this._navigation) {
    listenTo(_navigation.baseRouteStream, (route) {
      emit(_selected, switch (route) {
        CasesRoute() || CaseRoute() => MenuItem.cases,
        _ => null,
      });
    });
  }

  final NavigationService _navigation;

  late final _selected = own(BehaviorSubject<MenuItem?>.seeded(null));

  ValueStream<MenuItem?> get selected => _selected.stream;

  // handleAction ...
}
```

## Entering a route

`enter(route)` is called once by the coordinator, right after it creates the controller and before the page is built. Override it with your route type as the parameter; the base declares it `covariant`, so no cast is needed. Use it to keep the route's params and start loading, usually by dispatching an action:

```dart
@override
void enter(CaseRoute route) => dispatch(LoadCase(route.id));
```

Do not load in the constructor. The constructor runs before the controller knows its route, and tests build controllers without one.

## Staying on the page when params change

By default, when the shown route changes from `CaseRoute(1)` to `CaseRoute(2)`, the coordinator disposes the controller and creates a new one. The page is built again from scratch.

To keep the controller and its state, implement `RouteUpdatable<R>`. The coordinator then calls `update(route)` instead. It is not called for an equal route, and never together with `enter` for the same change.

```dart
class CaseController extends Controller<CaseAction>
    implements RouteUpdatable<CaseRoute> {
  // ...

  @override
  void enter(CaseRoute route) => dispatch(LoadCase(route.id));

  @override
  void update(CaseRoute route) => dispatch(LoadCase(route.id));
}
```

This works for modal routes too.

## Errors

Every error thrown by `handleAction`, sync or async, goes to `onError(error, stackTrace)`. This includes an error that arrives after the controller is disposed. The default logs it with `appLogger.error`. Never rethrow from `onError`.

To show errors as notices, override it and pass them to the `ErrorPolicy`, which you take in the constructor:

```dart
@override
void onError(Object error, StackTrace stackTrace) {
  _errors.handle(error, stackTrace);
}
```

Errors you expect, such as a refused sign-in, are better caught in `handleAction` and shown inline. [errors.md](errors.md) covers both.

## Disposal

The coordinator disposes a route or layout controller when it is no longer shown. `dispose()` is idempotent, and `isDisposed` tells you whether it has run. You rarely need to override it, because `own` covers most resources. If you do override it, call `super.dispose()`.

## Layout controllers

A `LayoutBinding` has its own controller, created before the route's controller and kept while the following routes share the same layout. It gets no `enter`, because a layout is not a route. A page inside a layout can read both controllers with `context.read`. See [routing.md](routing.md), "Layouts".

## Child controllers

Part of a page can have its own controller, owned by the page's controller. The child reports to the parent through streams. See [sub_controllers.md](sub_controllers.md).
