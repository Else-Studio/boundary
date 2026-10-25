## 0.5.0 (unreleased)

*   `LeaveGuard` lets a page veto or confirm leaving through `mayLeave` and report `hasUnsavedChanges`.
*   `NavigationService.addLeaveGuard` registers a guard until the returned `Disposable` is disposed; `hasLeaveGuards` and `hasUnsavedChanges` reflect the registered set.
*   `NavigationService.redirectTo` requests a route without asking leave guards (for the coordinator's own redirects).
*   Leave guards run on `navigateTo`, `navigateBackOrLogin`, `dismissModal`, `retryLastNavigation` and `navigateUp`; they skip when opening a modal over a page, when the target equals the shown route, and on `routerSetNewPath` / `syncBaseConfiguration` / `clearRequest` / `redirectTo`.
*   `CoreRouterDelegate.popRoute` with leave guards routes a modal's system back through `NavigationService.navigateUp` instead of popping the Navigator first.
*   Web unload warning: conditional import (`dart.library.js_interop`) attaches a `beforeunload` listener while any guard has unsaved changes.
*   New dependency: `web: 1.1.1` (web unload warning).
*   `FormLeaveGuard` connects a `FormSession` to leave checks: flush first, then the app's `confirm` when that fails or the form is invalid.
*   New dependency: `reactive_forms: ^18.2.2`.
*   `forms.dart` entry library exports form helpers; not exported from `boundary.dart`.
*   `FormSession` wraps a reactive_forms `FormGroup` with debounced auto-save, `flush`, `retry`, `patchFromServer` and `applyViolations`.
*   `SaveStatus` is `idle`, `dirty`, `invalid`, `saving`, `saved` or `error`.
*   `FormSession.applyViolations` maps `HttpValidationProblem` fields onto control `server` errors and returns unmatched violations.
*   `Disposable` is a core interface for anything a controller can own and release with `dispose()`.
*   `Controller.own` also accepts `Disposable` and reactive_forms `AbstractControl`.
*   `Notice`, `NoticeLevel` and `NoticeService` are new: a broadcast stream of notices for the UI.
*   `NoticeSnackBarListener` shows each notice as a `SnackBar` through the nearest `ScaffoldMessenger`.
*   `ErrorPolicy.handle` turns an error into a notice, a page when `pageFor` returns one, or nothing for `SessionTerminatedException`.
*   `PolicyErrors` mixin sends a controller's `onError` through `ErrorPolicy`.
*   `AppCoordinatorDelegate.createErrorPolicy` supplies the `ErrorPolicy` the coordinator registers with `NoticeService`.
*   `AsyncResultBuilder` renders an `AsyncResult` stream (loading, data, failure, empty).
*   `HttpProblem.extensions` keeps problem+json members the model does not name.
*   `CredentialsRejectedException` is a 401 on a call that needed no token; `requireAuth: true` still yields `SessionTerminatedException`.
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
*   `RouteUpdatable<R>` (was `RouteAware`) controllers get `update(route)` when their route type returns with different params and are kept; other controllers are recreated.
*   `Controller.adopt(child)` sets the parent and owns the child for disposal with the parent.
*   `Controller.slot` and `ControllerSlot` hold zero or one keyed child at a time; the slot disposes replaced children.
*   `ControllerSlotBuilder` builds the current slot child under `Provider` and an `ObjectKey`.
*   `ControllerFactory` and `addControllerFactory` register one create-function per child type in the injector.
*   `Controller.listenTo(stream, onData)` owns the subscription and routes handler and stream errors to `onError`.
*   A living adopted or slotted child's default `onError` forwards to its parent; an error after the child is disposed is logged.
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
*   `AuthState` is `AuthUnknown`, `Authenticated(session)` or `SignedOut(reason)`; the coordinator reads it from `AuthService.authState` instead of `userStream`.
*   `AuthSession({subject})` is who is signed in; apps may extend it.
*   `SignedOutReason` is `noSession`, `expired` or `signedOut`.
*   `AccessTokenProvider` has `accessToken()` and `refreshAfterUnauthorized(rejectedToken)`.
*   `AuthService` is now a small interface: `authState`, `initialize()`, `signOut()` and `dispose()`, on top of `AccessTokenProvider`.
*   `HttpService(AccessTokenProvider, http.BaseClient)` sends `Authorization: Bearer`; a 401 goes to the provider and is retried once with its new token, a second 401 is reported to the provider and thrown, and with no token a 401 is thrown without sending.
*   `HttpService.postMultipart` sends once: no 401 retry and no 429 retry.
*   `HttpException.requireAuth` says whether the call needed a token.
*   `AppCoordinator` creates the no-state fallback controller once and disposes it with the first base controller or with the coordinator.
*   Removed: the old `AuthService` members (`userStream`, `isLoading`, `getAuthenticatedClient`, registration, data policy and session messages, `clearLoggedOutStateAndPrepareForPolicyCheck`).
*   Removed: `User`.
*   Removed: `AuthError` and its subclasses.
*   Removed: `RegisteredUserInfo`.
*   Removed: `BaseAuthService`; the OAuth service returns in `oauth.dart`.
*   Removed: `HttpService.getBearerToken`.


*   `StoredTokenAuthService<C>` is an `AuthService` for a long-lived token: the app supplies the login call and a `CredentialStore`; a stored token means signed in at start, and the first 401 signs out.
*   `TokenGrant` is what the app's login call returns: a token and an optional subject.
*   `CredentialStore` keeps one string for `StoredTokenAuthService`; the app supplies a secure one.
*   `SharedPreferencesCredentialStore` is a `CredentialStore` in SharedPreferences. It is not secure; use it for development and tests.
*   `PostAuthRedirectStore` and `InMemoryPostAuthRedirectStore` keep the post-auth redirect; in memory by default.
*   `NavigationService(redirectStore:)` takes the redirect store; null means in memory.
*   `AppCoordinatorDelegate.createPostAuthRedirectStore()` supplies the store `NavigationService` uses.
*   `NavigationService` no longer keeps the post-auth redirect in SharedPreferences under `post_auth_redirect_intent`, and the 5-minute expiry is removed.
*   `oauth.dart` is a new entry library (not exported from `boundary.dart`) for the deprecated web-only OAuth adapter.
*   `OAuthAuthService` is a deprecated, web-only `AuthService` using OAuth2 PKCE and JWKS.
*   `OAuthConfig` replaces the old `dotenv` keys; `extraAuthorizationParameters` replaces `embedded` and `email`.
*   `TokenVerifier` and `JwksTokenVerifier` verify access tokens (JWKS RS256 by `kid`).
*   `SharedPreferencesPostAuthRedirectStore` keeps the post-auth redirect across an OAuth page leave, with a 5-minute lifetime.
*   Removed: the `flutter_dotenv` dependency.
*   `testing.dart` is a new entry library (not exported from `boundary.dart`) with test doubles for apps; it does not depend on `flutter_test`.
*   `pumpEventQueue()` runs queued microtasks and zero-delay timers in a test without `flutter_test`.
*   `FakeAuthService` is a controllable `AuthService` and `AccessTokenProvider` for tests.
*   `RecordingNavigationService` is a real `NavigationService` that records every request it emits.
*   `FakeHttpBackend` serves canned responses to an `HttpService` and records the requests it receives.
*   `ControllerHarness` dispatches actions to a controller to the end and records its streams.
*   Removed: `NavigationService.retryLastNavigation`; call `dismissModal()` instead.
*   Removed: `NavigationService.clearRequest`; the coordinator ignores a null request.

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
