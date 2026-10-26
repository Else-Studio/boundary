## 0.5.0

Boundary becomes a generic framework. This release breaks most of the 0.4 API. Where a change made earlier in this release was later reversed, only the final behaviour is listed.

### General

*   Entry libraries: `boundary.dart`, `forms.dart`, `testing.dart`, `formatters.dart` and `oauth.dart`. Only `boundary.dart` holds the core; the others are not exported from it.
*   `pubspec.yaml` description: "A Flutter framework for controllers, routing, and forms."
*   `AppConfig` keeps only `baseUrl` and `debounceTime`; `publicWebOrigin`, `sseWatchdogTimeout` and `sseMinRetryDelay` are removed.
*   `Error<T>` is now `Failure<T>`, so `dart:core` `Error` is no longer shadowed. `Failure.toString()` prints only the error.
*   `boundaryLogLevel` and `export LogLevel` added: tests and apps set the lowest level `useLogger` prints; quiet loggers still drop verbose and debug.
*   `AppFormatters` moved to `formatters.dart`; it is no longer exported from `boundary.dart`. Its methods and results are unchanged.
*   `AppFormatters.formatCurrency` requires `symbol`; the `'€ '` default is removed.
*   `LocaleService` is no longer exported, registered or used. The file stays as a reference; its conditional import is `dart.library.html`.
*   New dependencies: `provider: ^6.1.5+1`, `reactive_forms: ^18.2.2`, `web: 1.1.1` (web unload warning).
*   Removed dependency: `flutter_dotenv`.

### Controllers

*   `Controller.handleAction` returns `FutureOr<void>`, so it can be `async`; actions still run concurrently.
*   `Controller.onError(error, stackTrace)` receives every action error, sync or async; the default logs it.
*   `Controller.own(resource)` registers subscriptions, stream controllers and subjects, timers, `CompositeSubscription`s, child controllers, `ChangeNotifier`s, reactive_forms `AbstractControl`s and `Disposable`s for disposal, in reverse order.
*   `Disposable` is a core interface for anything a controller can own and release with `dispose()`.
*   `Controller.emit(target, value)` adds to a stream controller unless the controller is disposed or the target is closed.
*   `Controller.isDisposed` is public, and `Controller.dispose()` is idempotent.
*   `Controller.enter(route)` is called once by the coordinator right after it creates a controller; the default does nothing.
*   `RouteUpdatable<R>` (was `RouteAware`) controllers get `update(route)` when their route type returns with different params and are kept; other controllers are recreated.
*   `Controller.adopt(child)` sets the parent and owns the child for disposal with the parent.
*   `Controller.slot` and `ControllerSlot` hold zero or one keyed child at a time; the slot disposes replaced children.
*   `ControllerSlotBuilder` builds the current slot child under `Provider` and an `ObjectKey`.
*   `ControllerFactory` and `addControllerFactory` register one create-function per child type in the injector.
*   `Controller.listenTo(stream, onData)` owns the subscription and routes handler and stream errors to `onError`.
*   A child controller's default `onError` logs the error and does not forward it to the parent.
*   `AsyncResultBuilder` renders an `AsyncResult` stream (loading, data, failure, empty).

### Routing

*   `ConfigurationBase` routes compare by `runtimeType` and `uri`; `NotFoundRoute` also compares `originalUrl` and `ErrorRoute` also compares `problem`.
*   `ConfigurationBase.pathTemplate` (abstract) and `params` are new; `uri` is built from them and may still be overridden. The static `pathTemplate` on `NotFoundRoute` and `ErrorRoute` is now `path`.
*   `buildRouteUri(pathTemplate, params)` fills `:name` segments (encoded) and puts the other params in the query.
*   `RouteBinding<R, C>` records one destination: `path`, `parse`, `controller` and `page`, plus `access`, `transient` and `layout`.
*   `RouteBinding.createController(injector, route)` creates the controller and calls `enter`; `RouteBinding.buildView(controller)` wraps the page in `Provider<C>.value`, so pages read their controller with `context.read<C>()`.
*   `RouteTable(bindings)` parses a URL into a route (a parse that throws gives `NotFoundRoute`) and finds a route's binding with `bindingFor`.
*   `AppRouteInformationParser(RouteTable)` replaces `AppRouteInformationParser({routeMap, defaultRoute})`.
*   `AppCoordinatorDelegate.routes` lists every destination as `RouteBinding`s, and `AppCoordinator.routeTable` is the `RouteTable` built from it.
*   `NavigationService({required delegate, required routes, redirectStore})` parses the stored post-auth redirect with the `RouteTable`.
*   `RouteTable` appends `defaultErrorRouteBinding` and `defaultNotFoundRouteBinding` for the `ErrorRoute` and `NotFoundRoute` an app does not bind. Both are `public`. `DefaultPageController`, `DefaultErrorPage` and `DefaultNotFoundPage` are exported from `boundary.dart`, with English texts.
*   `RouteAccess` (`public`, `guestOnly`, `protected`) is new; `RouteBinding.access` sets it, and defaults to `protected`.
*   The coordinator applies one access table: when signed out, a `public` route is now shown, as is a `guestOnly` route, and only `protected` routes go to login; a signed-in user on a `guestOnly` route goes to `getPostLoginDefaultRoute()`.
*   `RouteBinding.transient` keeps a route out of the "last base" in `NavigationService`; `RouteTable.isTransient(route)` reads it (false for a route with no binding).
*   `GuardResult` (`allow`, `redirect`), `RouteGuard` and `AppCoordinatorDelegate.createGuards(injector)` are new: guards run in order, and the first redirect restarts resolution at the access step.
*   `ErrorRoute.message` from the coordinator is an English sentence: "The session could not be checked." (auth stream error), "A page check failed." (a guard throws), "Opening that page kept redirecting." (more than 5 guard redirects) and "The app could not decide which page to show." (no base controller).
*   `LayoutBinding(controller, builder)` is new: a layout around pages with its own controller, provided with `Provider<C>.value`.
*   `RouteBinding.layout` names a `LayoutBinding`; bindings that hold the identical instance share it. The coordinator creates the layout controller before the route's controller, keeps it while consecutive base routes share the layout, and disposes it when a route without it is shown; a modal never changes the layout.
*   `AppCoordinator.layoutController` is the current base route's layout controller, or null.
*   `ConfigurationBase.parent` is new: where back goes from a route; null for a top route.
*   `NavigationService.navigateUp()` dismisses a shown modal, or else goes to the shown base route's parent; it returns false and requests nothing when there is neither.
*   `CoreRouterDelegate.popRoute()` (system back) pops a shown modal, or else calls `navigateUp()`; the app exits only when the route has no parent. With leave guards registered, a modal's system back also goes through `navigateUp()`.
*   `NavigationService.baseRouteStream` and `modalRouteStream` stream the resolved routes, after redirects.
*   `NavigationService.onRouteResolved` is called by `AppCoordinator` each time what it shows changes.
*   `LeaveGuard` lets a page veto or confirm leaving through `mayLeave` and report `hasUnsavedChanges`.
*   `NavigationService.addLeaveGuard` registers a guard until the returned `Disposable` is disposed; `hasLeaveGuards` and `hasUnsavedChanges` reflect the registered set.
*   Leave guards run on `navigateTo`, `navigateBackOrLogin`, `dismissModal` and `navigateUp`; they skip when opening a modal over a page, when the target equals the shown route, and on `routerSetNewPath`, `syncBaseConfiguration` and `redirectTo`.
*   `NavigationService.redirectTo` requests a route without asking leave guards (for the coordinator's own redirects).
*   Web unload warning: a conditional import (`dart.library.js_interop`) attaches a `beforeunload` listener while any guard has unsaved changes.
*   `CoreRouterDelegate` shows the coordinator's own base widget when there is no base configuration, instead of its own spinner.
*   `router.dart` uses `onDidRemovePage` in place of the deprecated `onPopPage`; system back on a modal still calls `dismissModal()`.
*   `AppCoordinator` creates the no-state fallback controller once and disposes it with the first base controller or with the coordinator.

### Auth

*   `AuthState` is `AuthUnknown`, `Authenticated(session)` or `SignedOut(reason)`; the coordinator reads it from `AuthService.authState` instead of `userStream`.
*   `AuthSession({subject})` is who is signed in; apps may extend it.
*   `SignedOutReason` is `noSession`, `expired` or `signedOut`.
*   `AccessTokenProvider` has `accessToken()` and `refreshAfterUnauthorized(rejectedToken)`.
*   `AuthService` is now a small interface: `authState`, `initialize()`, `signOut()` and `dispose()`, on top of `AccessTokenProvider`.
*   `StoredTokenAuthService<C>` is an `AuthService` for a long-lived token: the app supplies the login call and a `CredentialStore`; a stored token means signed in at start, and the first 401 signs out.
*   `TokenGrant` is what the app's login call returns: a token and an optional subject.
*   `CredentialStore` keeps one string for `StoredTokenAuthService`; the app supplies a secure one.
*   `SharedPreferencesCredentialStore` is a `CredentialStore` in SharedPreferences. It is not secure; use it for development and tests.
*   `PostAuthRedirectStore` and `InMemoryPostAuthRedirectStore` keep the post-auth redirect; in memory by default.
*   `AppCoordinatorDelegate.createPostAuthRedirectStore()` supplies the store `NavigationService` uses.
*   `NavigationService` no longer keeps the post-auth redirect in SharedPreferences under `post_auth_redirect_intent`, and the 5-minute expiry is removed.
*   `oauth.dart` holds the deprecated web-only OAuth adapter: `OAuthAuthService` (OAuth2 PKCE and JWKS), configured by `OAuthConfig`, which replaces the old `dotenv` keys; `extraAuthorizationParameters` replaces `embedded` and `email`. It sends no `ui_locales` parameter.
*   `TokenVerifier` and `JwksTokenVerifier` verify access tokens (JWKS RS256 by `kid`).
*   `SharedPreferencesPostAuthRedirectStore` keeps the post-auth redirect across an OAuth page leave, with a 5-minute lifetime.

### HTTP and errors

*   `HttpService(AccessTokenProvider, http.BaseClient)` sends `Authorization: Bearer`; a 401 goes to the provider and is retried once with its new token, a second 401 is reported to the provider and thrown, and with no token a 401 is thrown without sending. It sends no `Accept-Language` header.
*   `HttpService.postMultipart` sends once: no 401 retry and no 429 retry.
*   `HttpException.requireAuth` says whether the call needed a token.
*   `CredentialsRejectedException` is a 401 on a call that needed no token; `requireAuth: true` still yields `SessionTerminatedException`.
*   `HttpProblem.extensions` keeps problem+json members the model does not name.
*   `Notice`, `NoticeLevel` and `NoticeService` are new: a broadcast stream of notices for the UI.
*   `NoticeSnackBarListener` shows each notice as a `SnackBar` through the nearest `ScaffoldMessenger`.
*   `ErrorPolicy.handle` turns an error into a notice, a page when `pageFor` returns one, or nothing for `SessionTerminatedException`. A controller opts in by overriding `onError` and calling `handle`.
*   `AppCoordinatorDelegate.createErrorPolicy` supplies the `ErrorPolicy` the coordinator registers with `NoticeService`.

### Forms

*   `FormSession` wraps a reactive_forms `FormGroup` with debounced auto-save, `flush`, `retry`, `patchFromServer` and `applyViolations`.
*   `SaveStatus` is `idle`, `dirty`, `invalid`, `saving`, `saved` or `error`.
*   `FormSession.applyViolations` maps `HttpValidationProblem` fields onto control `server` errors and returns unmatched violations.
*   `FormLeaveGuard` connects a `FormSession` to leave checks: flush first, then the app's `confirm` when that fails or the form is invalid.

### Testing

*   `testing.dart` has test doubles for apps; it does not depend on `flutter_test`.
*   `pumpEventQueue()` runs queued microtasks and zero-delay timers in a test without `flutter_test`.
*   `FakeAuthService` is a controllable `AuthService` and `AccessTokenProvider` for tests.
*   `RecordingNavigationService` is a real `NavigationService` that records every request it emits.
*   `FakeHttpBackend` serves canned responses to an `HttpService` and records the requests it receives.
*   `ControllerHarness` dispatches actions to a controller to the end and records its streams.

### Removed

*   `Controller.addSubscription`; use `own`.
*   The `PolicyErrors` mixin; a controller overrides `onError` and calls `ErrorPolicy.handle`.
*   `Failure.messageKey`.
*   `ConfigurationBuilder`, `AppRouteInformationParser.parseUri`, `NotFoundRoute.create` and `ErrorRoute.create`.
*   `NavigationServiceDelegate.parseUri`, `AppCoordinatorDelegate.createControllerForConfiguration` and `AppCoordinatorDelegate.mapControllerToWidget`.
*   `ConfigurationBase.isProtected` and `protected`, `NavigationServiceDelegate.isAuthCallbackRoute`, `AppCoordinatorDelegate.isPublicOnlyRoute`, `isLogoutRoute`, `getResetPasswordRoute` and `resolveAppSpecificAuthState`.
*   `LoggedOut.emailForResetPassword` and the `resetPassword` parameter of `confirmLocalLogout()`.
*   `AppCoordinatorDelegate.shellController` and `AppCoordinator.shellController`; apps declare a `LayoutBinding` per route instead.
*   `AppCoordinatorDelegate.shouldDisposeController`; every replaced base controller is now disposed.
*   The private long-lived controller cache; there is no keep-alive.
*   `NavigationService.retryLastNavigation`; call `dismissModal()` instead.
*   `NavigationService.clearRequest`; the coordinator ignores a null request.
*   `NoAnimationTransitionDelegate`; `NoAnimationPage` and `TransparentModalPage` stay.
*   `AppCoordinator.localeService` and the `LocaleService` registration.
*   The old `AuthService` members (`userStream`, `isLoading`, `getAuthenticatedClient`, registration, data policy and session messages, `clearLoggedOutStateAndPrepareForPolicyCheck`).
*   `User`, `AuthError` and its subclasses, and `RegisteredUserInfo`.
*   `BaseAuthService`; the OAuth service is `OAuthAuthService` in `oauth.dart`.
*   `HttpService.getBearerToken`.

## 0.4.x and earlier

The VH-era framework; see git history.
