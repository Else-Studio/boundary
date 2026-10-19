## 0.5.0 (unreleased)

*   `Error<T>` is now `Failure<T>`, so `dart:core` `Error` is no longer shadowed.
*   `boundaryLogLevel` and `export LogLevel` added: tests and apps set the lowest level `useLogger` prints; quiet loggers still drop verbose and debug.
*   `router.dart` uses `onDidRemovePage` in place of the deprecated `onPopPage`; system back on a modal still calls `dismissModal()`.
*   `HttpService(AuthService, http.BaseClient)`: no `LocaleService`, and no `Accept-Language` header.
*   `BaseAuthService({required loggerLabel})`: no `LocaleService`, and no `ui_locales` query parameter.
*   `AppCoordinator.localeService` and the `LocaleService` registration are removed; `locale_service.dart` is no longer exported from `boundary.dart`.
*   `AppConfig` keeps only `baseUrl` and `debounceTime`; `publicWebOrigin`, `sseWatchdogTimeout` and `sseMinRetryDelay` are removed.
*   `AppFormatters.formatCurrency` requires `symbol`; the `'€ '` default is removed.
*   `Controller.handleAction` returns `FutureOr<void>`, so it can be `async`; actions still run concurrently.
*   `Controller.onError(error, stackTrace)` receives every action error, sync or async; the default logs it.
*   `Controller.own(resource)` registers subscriptions, stream controllers and subjects, timers, `CompositeSubscription`s, child controllers and `ChangeNotifier`s for disposal, in reverse order.
*   `Controller.emit(target, value)` adds to a stream controller unless the controller is disposed or the target is closed.
*   `Controller.isDisposed` is public, and `Controller.dispose()` is idempotent.
*   `Controller.addSubscription` is removed; use `own`.
*   `ConfigurationBase` routes compare by `runtimeType` and `uri`; `NotFoundRoute` also compares `originalUrl` and `ErrorRoute` also compares `problem`.
*   `ConfigurationBase.pathTemplate` (abstract) and `params` are new; `uri` is built from them and may still be overridden.
*   `buildRouteUri(pathTemplate, params)` fills `:name` segments (encoded) and puts the other params in the query.
*   `RouteBinding<R, C>` records one destination: `path`, `parse`, `controller` and `page`.
*   `RouteTable(bindings)` parses a URL into a route (a parse that throws gives `NotFoundRoute`) and finds a route's binding with `bindingFor`.
*   `AppRouteInformationParser(RouteTable)` replaces `AppRouteInformationParser({routeMap, defaultRoute})`.
*   Removed: `ConfigurationBuilder`, `AppRouteInformationParser.parseUri`, `NotFoundRoute.create`, `ErrorRoute.create`; the static `pathTemplate` on `NotFoundRoute` and `ErrorRoute` is now `path`.
*   `Controller.enter(route)` is called once by the coordinator right after it creates a controller; the default does nothing.
*   `RouteBinding.createController(injector, route)` creates the controller and calls `enter`; `RouteBinding.buildView(controller)` wraps the page in `Provider<C>.value`, so pages read their controller with `context.read<C>()`.
*   New dependency: `provider: ^6.1.5+1`.
*   `AppCoordinatorDelegate.routes` lists every destination as `RouteBinding`s, and `AppCoordinator.routeTable` is the `RouteTable` built from it.
*   `NavigationService({required delegate, required routes})` parses the stored post-auth redirect with the `RouteTable`.
*   `RouteTable` appends `defaultErrorRouteBinding` and `defaultNotFoundRouteBinding` for the `ErrorRoute` and `NotFoundRoute` an app does not bind; `DefaultPageController`, `DefaultErrorPage` and `DefaultNotFoundPage` are exported from `boundary.dart`.
*   Removed: `NavigationServiceDelegate.parseUri`, `AppCoordinatorDelegate.createControllerForConfiguration` and `AppCoordinatorDelegate.mapControllerToWidget`.
*   `RouteAware<R>` controllers get `update(route)` when their route type returns with different params and are kept; other controllers are recreated.
*   `NavigationService.baseRouteStream` and `modalRouteStream` stream the resolved routes, after redirects.
*   `NavigationService.onRouteResolved` is called by `AppCoordinator` each time what it shows changes.
*   `RouteAccess` (`public`, `guestOnly`, `protected`) is new; `RouteBinding.access` sets it, and defaults to `protected`.
*   `RouteBinding.transient` keeps a route out of the "last base" in `NavigationService`; `RouteTable.isTransient(route)` reads it (false for a route with no binding).
*   `GuardResult` (`allow`, `redirect`), `RouteGuard` and `AppCoordinatorDelegate.createGuards(injector)` are new: guards run in order, the first redirect restarts resolution at the access step, more than 5 redirects show `error.navigation.redirectLoop` and a guard that throws shows `error.navigation.guardFailed`.
*   The coordinator applies one access table: when signed out, a `public` route is now shown, as is a `guestOnly` route, and only `protected` routes go to login; a signed-in user on a `guestOnly` route goes to `getPostLoginDefaultRoute()`.
*   `defaultErrorRouteBinding` and `defaultNotFoundRouteBinding` are `public`.
*   Removed: `ConfigurationBase.isProtected` and `protected`, `NavigationServiceDelegate.isAuthCallbackRoute`, `AppCoordinatorDelegate.isPublicOnlyRoute`, `isLogoutRoute`, `getResetPasswordRoute` and `resolveAppSpecificAuthState`.
*   Removed: `LoggedOut.emailForResetPassword` and the `resetPassword` parameter of `confirmLocalLogout()`.
*   `LayoutBinding(controller, builder)` is new: a layout around pages with its own controller, provided with `Provider<C>.value`.
*   `RouteBinding.layout` names a `LayoutBinding`; bindings that hold the identical instance share it. The coordinator creates the layout controller before the route's controller, keeps it while consecutive base routes share the layout, and disposes it when a route without it is shown; a modal never changes the layout.
*   `AppCoordinator.layoutController` is the current base route's layout controller, or null.
*   Removed: `AppCoordinatorDelegate.shellController`; apps declare a `LayoutBinding` per route instead.
*   Removed: `AppCoordinatorDelegate.shouldDisposeController`; every replaced base controller is now disposed.
*   Removed: `AppCoordinator.shellController`.
*   Removed: the private `_longLivedControllerCache`; there is no keep-alive.
*   `ConfigurationBase.parent` is new: where back goes from a route; null for a top route.
*   `NavigationService.navigateUp()` dismisses a shown modal, or else goes to the shown base route's parent; it returns false and requests nothing when there is neither.
*   `CoreRouterDelegate.popRoute()` (system back) pops a shown modal, or else calls `navigateUp()`; the app exits only when the route has no parent.

## 0.4.1

### Improvements & Bug Fixes
*   **Service Module**: Improved service management based on meeting feedback (cities support, enhanced filtering, etc).
*   **Task Module**: Fixed a critical blockage in the task creation process.

## 0.4.0

### Sales & Customer Module Expansion
*   **Customer Module Completion**: Finalized `CustomerDetail` feature for creating and editing customers and contacts.
*   **Pipeline Visualization**: 
    *   Implemented Kanban Pipelines for Leads and Product Requests.
    *   Integrated creation modals for Leads and Product Requests.
*   **Lead & Product Request Workbenches**:
    *   Developed immersive workspaces for managing Leads and Product Requests.
    *   Extracted `WorkbenchLayout` and `ScopedTaskBoardController` for high code reuse.
*   **Navigation**:
    *   Implemented a toggle to hide WIP features (Projects, Enquiry, Product Request, Customer) in the shell.

## 0.0.1

* Initial release.
