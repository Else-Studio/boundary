# Architecture

This page explains how a boundary app is put together and why. It covers the layers, the objects that run the app, what happens at startup, how the coordinator decides what to show, and the life of a controller. The rules that follow from this are in [building_with_boundary.md](building_with_boundary.md).

## The three layers

**Services** are the app's connection to the outside world. An API client, the auth service and a local database are services. They are long-lived singletons in the injector. They hold no screen state, though a service may keep shared data, such as the signed-in user, on a stream.

**Controllers** hold the logic of one screen, one layout, or one part of a screen. A controller receives actions, calls services, and publishes its state on streams. It lives as long as its screen is shown.

**Views** are Flutter widgets. A view draws the controller's streams and turns taps and edits into actions. It holds no logic of its own.

Why this split:

- **Logic can be tested without widgets.** A controller is a plain Dart object with actions in and streams out. A test builds it with test doubles, dispatches actions and reads the streams.
- **Every change has one entry point.** All work starts in `handleAction`, so you can find and log every intent in one place.
- **Views stay cheap to change.** Redesigning a screen does not touch its logic, and the same controller can serve a phone and a desktop layout.

## The objects that run the app

| Object | What it does |
|---|---|
| `AppCoordinator` | Owns the injector. Combines the requested route with the auth state, decides what to show, and creates and disposes controllers. One per app, made in `main()`. |
| `AppCoordinatorDelegate` | Your app's part: its routes, its dependencies, its guards, its login and home routes. You subclass it once. |
| `RouteTable` | The list of `RouteBinding`s. Parses a URL into a route and finds a route's binding. Built by the coordinator from `delegate.routes`. |
| `RouteBinding` | One destination: path, how to parse params, how to build the controller and the page, who may see it, and its layout. |
| `LayoutBinding` | A frame around pages, such as an app bar with a menu, with its own controller. |
| `NavigationService` | Takes navigation requests, runs leave guards, keeps the post-sign-in redirect, and streams what is shown. Controllers inject it. |
| `AuthService` | Holds the auth state and provides the access token. The app chooses an implementation, usually `StoredTokenAuthService`. |
| `HttpService` | Sends HTTP requests with the bearer token, retries a 401 once after asking the auth service, and backs off on 429. |
| `BaseApiClient` | The base class for your API clients. Turns HTTP failures into typed exceptions. |
| `ErrorPolicy` | Turns an error into a notice or a page, for controllers that ask it to. |
| `NoticeService` | A stream of short messages for the user. `NoticeSnackBarListener` shows them as SnackBars. |
| `CoreRouterDelegate` | Flutter's router delegate. Builds the Navigator's pages from what the coordinator shows. |

## Startup

`AppCoordinator(delegate)` does this, in order:

1. Builds the `RouteTable` from `delegate.routes`. It appends the default error and not-found bindings unless the app binds those route types itself.
2. Registers boundary's services in the injector: `NoticeService`, `NavigationService`, `ErrorPolicy` (from `delegate.createErrorPolicy`), an `http.Client` as `BaseClient`, and `HttpService`.
3. Calls `delegate.registerDependencies(injector)`. The app registers its `AuthService`, its `AppConfig`, its API clients, other services and its controllers here. `HttpService` asks the injector for an `AuthService`, so the app must register one.
4. Commits the injector. Singletons are created now.
5. Calls `delegate.createGuards(injector)` once.
6. Starts listening to the auth state and to navigation requests, and calls `authService.initialize()`.

The platform then reports the start URL. `AppRouteInformationParser` parses it with the route table, and the coordinator resolves it.

### Dependency injection

The injector is `auto_injector`. Register in `registerDependencies`, before the commit, and read with `injector.get<T>()`:

| Register with | You get | Use it for |
|---|---|---|
| `add(Constructor.new)` | A new object on every `get`. | Controllers. |
| `addSingleton<T>(Constructor.new)` | One object, created at the commit. | Services and API clients. |
| `addLazySingleton<T>(Constructor.new)` | One object, created at the first `get`. | Services that are costly to create and not always needed. |
| `addInstance<T>(object)` | The object you built. | Config, and objects that need a hand-written setup. |

**Give a constructor tear-off, not a closure.** For `CaseApi.new`, the injector reads the constructor's parameter types and fills each parameter with the registered object of that type. You do not list the arguments, and a new constructor parameter needs no change to the registration.

- It fills every required parameter that is not nullable, positional or named.
- It leaves optional and nullable parameters alone. They get their default value or null.
- A required parameter whose type is not registered throws `UnregisteredInstance` when the object is first created. A `String`, a number or a callback is never registered.

Write a closure only for those cases: a parameter that is not in the injector, or a setup step such as the auth service's lazy login call in [auth.md](auth.md). For example, `injector.add(() => ReportController(injector.get<ReportApi>(), pageSize: 50))`.

Lookup is by the type you name. Register an object under the type that controllers will ask for, which is usually the interface. Register it a second time under its own type if some code needs the concrete class, as a login controller needs `StoredTokenAuthService` for `signIn`.

**Controllers are registered with `add`**: route controllers, layout controllers and child controllers. The coordinator disposes a controller when its page goes, and a disposed controller cannot be used again, so never register one as a singleton. A binding asks the injector for a new one when its route is shown:

```dart
// In registerDependencies:
injector.add(CasesController.new);

// In routes:
RouteBinding<CasesRoute, CasesController>(
  path: CasesRoute.path,
  parse: (_) => const CasesRoute(),
  controller: (i) => i.get<CasesController>(),
  page: const CasesPage(),
),
```

## How the coordinator decides what to show

Each time the requested route or the auth state changes, the coordinator resolves them, one change at a time, in this order:

1. **Auth unknown** (before `initialize()` has finished): the requested route is shown as it is. No access rule or guard runs yet. They run when the auth state settles. This is why an app binds a root route at `/` that shows a loading page. It is also why a protected page's controller may be created before auth is known. With `StoredTokenAuthService`, calls that need a token wait until the auth state settles.
2. **Auth stream error:** an `ErrorRoute` with the message "The session could not be checked."
3. **Signed in:** a route saved before sign-in, if any, replaces the request.
4. **Access:** see the table below.
5. **Guards:** each guard of `createGuards` runs in order. The first redirect replaces the route, and resolution goes back to step 4. More than five redirects give an `ErrorRoute`, and so does a guard that throws.
6. **Show:** a modal route is shown over the current base page. Any other route becomes the base page, and any modal closes.

| Access | Signed in | Not signed in |
|---|---|---|
| `public` | shown | shown |
| `guestOnly` | replaced by `getPostLoginDefaultRoute()` | shown |
| `protected` (the default) | shown | saved for after sign-in, then replaced by `getLoginRoute()` |

A route built with `isRoot: true` is replaced by the post-login route when the user is signed in. After the user signs out, a protected route goes to login and the route is not saved.

When the shown route changes, the coordinator:

- updates the layout: it keeps the layout controller when the new route has the identical `LayoutBinding`, and otherwise disposes it and creates the new one;
- keeps a `RouteUpdatable` controller and calls `update(route)` when the route type is the same and only the params differ; otherwise it creates the new controller and calls `enter(route)`;
- disposes replaced controllers after the next frame, so the old page can finish building;
- reports the shown routes to `NavigationService.baseRouteStream` and `modalRouteStream`, then rebuilds the router.

[routing.md](routing.md) covers bindings, guards, layouts, modals and back navigation in detail.

## The life of a controller

| Moment | What happens |
|---|---|
| Created | The binding's `controller` closure runs. The constructor takes its services. A layout controller is created before the route's controller. |
| `enter(route)` | Called once, right after creation and before the page is built. Start loading here. Layout controllers get no `enter`. |
| Running | The page dispatches actions. Each runs `handleAction`. Errors go to `onError`. |
| `update(route)` | Only for `RouteUpdatable` controllers, when the same route type returns with other params. Called instead of creating a new controller. |
| Disposed | When its route or layout is no longer shown, after the next frame. Everything registered with `own` is released in reverse order. |

[controllers.md](controllers.md) shows how to write each part.

## Words used in these guides

| Word | Meaning |
|---|---|
| Route | An object of a `ConfigurationBase` subclass, such as `CaseRoute(12)`. It names a destination and carries its params. Routes with the same type and URI are equal. |
| Binding | The `RouteBinding` that says how to show a route type. |
| Base page | The main page. There is always one, once auth is known. |
| Modal | A route with `isModal: true`, shown over the base page. |
| Layout | A frame around base pages, with its own controller, declared by a `LayoutBinding`. |
| Parent | The route that back goes to from this route. |
| Transient | A binding flag. A transient route is never remembered as the page to go back to. |
| Guard | A `RouteGuard`: an app check that may send the user to another route. |
| Leave guard | A `LeaveGuard`: a check that may stop the user leaving the current page. |
| Notice | A short message for the user, shown as a SnackBar. |
| Slot | A holder in a parent controller for zero or one child controller, chosen by a key. |
