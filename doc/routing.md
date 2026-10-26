# Routing

In boundary, a destination is a route object, and a binding says how to show it. The `AppCoordinator` decides what to show from the requested route and the auth state. This page covers routes, bindings, navigating, access, guards, layouts, modals, back navigation and leave guards. For the order in which the coordinator applies these, see [architecture.md](architecture.md), "How the coordinator decides what to show".

## Routes

A route is a subclass of `ConfigurationBase`. It declares its path once as `static const path`, returns it from `pathTemplate`, and puts its values in `params`:

```dart
class CaseRoute extends ConfigurationBase {
  const CaseRoute(this.id);

  static const path = '/cases/:id';

  final int id;

  @override
  String get pathTemplate => path;

  @override
  Map<String, String> get params => {'id': '$id'};

  @override
  ConfigurationBase get parent => const CasesRoute();
}
```

- **`params`** fills each `:name` segment of the path. Values are URI-encoded. Names that match no segment become query parameters. A segment with no value throws an `ArgumentError`.
- **`uri`** is built from `pathTemplate` and `params`. The browser's address bar shows it, and the post-sign-in redirect stores it.
- **Equality:** two routes are equal when they have the same type and the same `uri`. If a route carries state that is not in its URI and that should make it a different route, override `==` and `hashCode`.
- **`parent`** is where back goes from this route. See "Back" below.

A route with no params only needs `path` and `pathTemplate`:

```dart
class CasesRoute extends ConfigurationBase {
  const CasesRoute();

  static const path = '/cases';

  @override
  String get pathTemplate => path;
}
```

### The root route

Bind a route at `/` with `isRoot: true`. The platform opens the app at `/`, so without a binding there the first page would be "Page not found". When the user is signed in, the coordinator replaces a root route with `getPostLoginDefaultRoute()`. While the auth state is still unknown, the root route's page is shown, so make it a loading page. Keep it `protected`, the default, so a signed-out user goes to login.

```dart
class RootRoute extends ConfigurationBase {
  const RootRoute() : super(isRoot: true);

  static const path = '/';

  @override
  String get pathTemplate => path;
}
```

## Bindings

Your delegate's `routes` getter lists one `RouteBinding` per route type:

```dart
RouteBinding<CaseRoute, CaseController>(
  path: CaseRoute.path,
  parse: (params) => CaseRoute(int.parse(params['id']!)),
  controller: (i) => CaseController(
    i.get<CaseRepository>(),
    i.get<NavigationService>(),
    i.get<ControllerFactory<NoteController>>(),
  ),
  page: const CasePage(),
  layout: shell,
),
```

| Field | Meaning |
|---|---|
| `path` | The route's `static const path`. Give the same constant, not a copy of the string. Showing a route whose `pathTemplate` differs from its binding's `path` throws a `StateError`. |
| `parse` | Builds the route from a URL's params: the path params, decoded, and the query params, all as strings. A path param wins over a query param of the same name. If `parse` throws, the URL shows "Page not found". |
| `controller` | Builds the controller from the injector. The coordinator then calls `enter(route)` on it. |
| `page` | The page widget. It is built under `Provider<C>.value`, so it reads its controller with `context.read<C>()`. |
| `access` | `public`, `guestOnly` or `protected`. Defaults to `protected`. |
| `transient` | When true, the route is never remembered as the page to go back to. Use it for pages like a success screen. Defaults to false. |
| `layout` | A `LayoutBinding` that frames the page. See "Layouts". |

Two bindings for the same route type throw an `ArgumentError`. Showing a route type with no binding throws a `StateError` that names the type.

**Bindings match a URL in list order.** The first binding whose path matches parses the URL, and no later binding is tried, even if its `parse` throws. Put fixed paths before paths with params that could match them:

```dart
// Before CaseRoute: '/cases/:id' would also match '/cases/new'.
RouteBinding<NewCaseRoute, NewCaseController>(path: NewCaseRoute.path, /* ... */),
RouteBinding<CaseRoute, CaseController>(path: CaseRoute.path, /* ... */),
```

A trailing slash is optional when matching. `/cases/` matches `/cases`.

### Error and not-found pages

Boundary appends two default bindings unless you bind the route type yourself:

- `ErrorRoute(message: ..., problem: ..., isSessionTermination: ...)` shows "Something went wrong", the message, and a "Back" button.
- `NotFoundRoute(originalUrl)` shows "Page not found", the URL, and a "Back" button.

"Back" calls `navigateBackOrLogin()`. To use your own pages, add a binding for `ErrorRoute` or `NotFoundRoute` with `access: RouteAccess.public`. To send the user to an error page yourself, navigate to an `ErrorRoute`.

## Navigating

Controllers inject `NavigationService` and call it from `handleAction`:

| Method | What it does |
|---|---|
| `navigateTo(route)` | Requests `route`. Leave guards run first. |
| `navigateUp()` | Closes a shown modal, or else goes to the shown page's `parent`. Returns false and does nothing when there is neither. |
| `dismissModal()` | Closes the modal: goes back to the last base page, or to the post-login route if there is none. |
| `navigateBackOrLogin()` | Goes to the last base page, or to login if there is none. |

The last base page is the last route requested that is not a modal, not an `ErrorRoute`, and not transient.

`NavigationService` also tells you what is shown, after redirects:

- `baseRouteStream`: the base route, or null before the first route is shown.
- `modalRouteStream`: the modal route, or null.

Both are `ValueStream`s that emit only on change. A layout controller can use them to highlight the current menu item. See [controllers.md](controllers.md), "Listening to other streams".

`redirectTo(route)` requests a route without asking leave guards. The coordinator uses it for its own redirects. Apps use `navigateTo`.

## Access and sign-in

Each binding's `access` decides who may see the route. The full table is in [architecture.md](architecture.md). In short:

- `public`: everyone.
- `guestOnly`: users who are not signed in. A signed-in user goes to `getPostLoginDefaultRoute()`. Use it for the login page.
- `protected`: signed-in users. Anyone else goes to `getLoginRoute()`, and the route they asked for is saved. After they sign in, they go there instead of the post-login route.

The saved route is kept by a `PostAuthRedirectStore`. The default keeps it in memory, which is enough unless sign-in leaves the app, as a web OAuth redirect does. Override `createPostAuthRedirectStore()` in the delegate to change it. A saved route at `/` is dropped. When the user signs out, the coordinator shows the login route and does not save the route they were on.

## Guards

A guard is an app rule that can send the user elsewhere, such as a role check. Implement `RouteGuard`:

```dart
/// Only admins may open AdminRoute. Every other route is allowed.
class AdminGuard implements RouteGuard {
  AdminGuard(this._profile);

  final ProfileService _profile;

  @override
  Future<GuardResult> check(ConfigurationBase route) async {
    if (route is! AdminRoute) return const GuardResult.allow();
    if (await _profile.isAdmin()) return const GuardResult.allow();
    return const GuardResult.redirect(CasesRoute());
  }
}
```

Create guards in the delegate. This runs once, after dependencies are registered:

```dart
@override
List<RouteGuard> createGuards(AutoInjector injector) => [
      AdminGuard(injector.get<ProfileService>()),
    ];
```

How guards run:

- They run on every route the coordinator is about to show, after the access step, including the login route and routes saved for after sign-in. Allow every route a guard does not care about.
- They run in list order. The first redirect wins. The redirect target goes through the access step and all the guards again.
- A guard is not given the auth state. Read what it needs from the services it was built with.
- Guards do not run while the auth state is unknown.
- More than five redirects in a row show an `ErrorRoute` ("Opening that page kept redirecting."). A guard that throws shows an `ErrorRoute` ("A page check failed."). A guard that always redirects to a route it also redirects from therefore ends on the error page.

## Layouts

A layout is a frame shared by several pages, such as an app bar with a sign-out button. Declare it once, with its controller and a builder that wraps the page:

```dart
final shell = LayoutBinding<ShellController>(
  controller: (i) => ShellController(i.get<AuthService>()),
  builder: (child) => ShellLayout(child: child),
);
```

Give the same instance to each binding that uses it: `layout: shell`. Two bindings share a layout only when they hold the identical `LayoutBinding` object, so declare it once, for example as a top-level `final`.

The layout widget reads its controller with `context.read`, and holds the `Scaffold`. Pages inside it do not build their own:

```dart
class ShellLayout extends StatelessWidget {
  const ShellLayout({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<ShellController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cases'),
        actions: [
          TextButton(
            onPressed: () => controller.dispatch(ShellAction.signOut),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: child,
    );
  }
}
```

How the layout controller lives:

- It is created before the route's controller. It gets no `enter`.
- It is kept while the next base routes share the same layout, so its state survives moving between those pages.
- It is disposed when a route without that layout is shown.
- A modal never changes the layout.
- A page inside the layout can read both its own controller and the layout's controller.

## Modals

A modal route is shown over the current base page. Pass `isModal: true`:

```dart
class NewCaseRoute extends ConfigurationBase {
  const NewCaseRoute() : super(isModal: true);

  static const path = '/cases/new';

  @override
  String get pathTemplate => path;

  @override
  ConfigurationBase get defaultBaseRoute => const CasesRoute();
}
```

Its binding is like any other. It is built with your `RouterPageBuilder.buildModalPage`, usually as a `TransparentModalPage`, and it ignores layouts.

- Open it with `navigateTo(const NewCaseRoute())`. Close it with `dismissModal()` or `navigateUp()`. Do not use `Navigator.pop` for a route modal.
- When the app opens directly on a modal's URL, there is no base page yet. The base becomes `defaultBaseRoute`, or the post-login route when that is null.
- Showing a different base route closes the modal.

A dialog that only asks a question, such as "Discard changes?", does not need a route. Show it with `showDialog` and close it with `Navigator.pop`.

## Back

Boundary keeps no history stack. Back goes up, to the route's `parent`, not to the previous page.

- `navigateUp()` closes a shown modal. Otherwise it goes to the shown base route's `parent`. A route with no parent is a top route, and `navigateUp()` returns false.
- System back, such as the Android back button, does the same. On a top route it leaves the app.
- `parent` is a getter, so it can use the route's params. For example, `NoteRoute(caseId, noteId).parent` can return `CaseRoute(caseId)`.

A back arrow on a page dispatches an action, and the controller calls `navigateUp()`.

## Leave guards

A leave guard lets a page stop the user from leaving, for example while a form has unsaved changes. Implement `LeaveGuard`, or use `FormLeaveGuard` from [forms.md](forms.md), and register it with the controller owning the registration:

```dart
own(navigation.addLeaveGuard(
  FormLeaveGuard(_session, confirm: dialogs.confirmDiscard),
));
```

`mayLeave()` returns true to let the navigation go ahead. `hasUnsavedChanges` drives the browser's "leave site?" warning on the web.

Leave guards run before `navigateTo`, `navigateUp`, `dismissModal`, `navigateBackOrLogin`, and system back. They do not run when:

- a modal opens over a page;
- the target is the route already shown;
- the coordinator redirects by itself, for example to login after sign-out;
- the platform changes the URL, as a deep link or the browser's back button does.

If a guard returns false or throws, the navigation is dropped. While guards are running, any other request from the methods above is dropped too.

## Setting up the router

`main()` connects the coordinator to Flutter's router:

```dart
late final CoreRouterDelegate router;
final coordinator = AppCoordinator(
  AppDelegate(dialogContext: () => router.navigatorKey.currentContext),
);
router = CoreRouterDelegate(
  appCoordinator: coordinator,
  pageBuilder: const AppPageBuilder(),
);

runApp(MaterialApp.router(
  routeInformationParser: AppRouteInformationParser(coordinator.routeTable),
  routerDelegate: router,
  // ...
));
```

`CoreRouterDelegate` needs a `RouterPageBuilder`, which turns each shown route into a Navigator page. Boundary provides `NoAnimationPage` for base pages and `TransparentModalPage` for modals:

```dart
class AppPageBuilder implements RouterPageBuilder {
  const AppPageBuilder();

  @override
  Page buildBasePage(
    BuildContext context,
    ConfigurationBase config,
    Widget contentWidget,
  ) =>
      NoAnimationPage(child: contentWidget);

  @override
  Page buildModalPage(
    BuildContext context,
    ConfigurationBase config,
    Widget contentWidget,
  ) =>
      TransparentModalPage(child: contentWidget);
}
```

`router.navigatorKey.currentContext` is the context that dialogs opened by controllers use. The `dialogContext` closure above passes it to the delegate. It is read only when a dialog opens, after the router exists. See [forms.md](forms.md) for a dialog service built on it.
