# Getting started

This guide builds a small app on boundary, step by step. The app signs in with an email and a password, lists cases, and opens one case on its own page. By the end you will have used each main part of the framework: routes and bindings, controllers and pages, a shared layout, the stored-token auth service, an API client, and error notices.

Every step shows the code to write. The guides in [`doc/`](doc/) explain each part in depth, and [`doc/building_with_boundary.md`](doc/building_with_boundary.md) lists the rules every feature follows.

## 1. Dependencies

Create a Flutter app, then add boundary and the packages your code will import directly:

```yaml
dependencies:
  flutter:
    sdk: flutter
  boundary:
    path: ../boundary # or a git dependency
  auto_injector: ^2.1.0
  provider: ^6.1.5+1
  reactive_forms: ^18.2.2
  rxdart: ^0.28.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.9
  mockito: ^5.5.1
```

Your app imports boundary through its entry libraries only:

- `package:boundary/boundary.dart` for everything in this guide;
- `package:boundary/forms.dart` for auto-saving forms;
- `package:boundary/testing.dart` in tests.

## 2. The app's configuration

Boundary asks the app for two settings through `AppConfig`: the API's base URL, and how long to wait after typing before saving a form.

```dart
class AppConfigImpl implements AppConfig {
  const AppConfigImpl();

  @override
  String get baseUrl => 'http://localhost:8080';

  @override
  Duration get debounceTime => const Duration(milliseconds: 800);
}
```

## 3. Routes

Each destination is a route class. A route declares its path once as `static const path`, and returns it from `pathTemplate`. A route with values in its path returns them from `params`. `parent` says where back goes.

```dart
/// `/`. Signed in, the coordinator replaces it with the post-login route.
class RootRoute extends ConfigurationBase {
  const RootRoute() : super(isRoot: true);

  static const path = '/';

  @override
  String get pathTemplate => path;
}

class LoginRoute extends ConfigurationBase {
  const LoginRoute();

  static const path = '/login';

  @override
  String get pathTemplate => path;
}

class CasesRoute extends ConfigurationBase {
  const CasesRoute();

  static const path = '/cases';

  @override
  String get pathTemplate => path;
}

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

The app opens at `/`, so `RootRoute` is bound there. While the stored session is being read, its page is shown. Once the user is known, the coordinator replaces it: with the cases list when signed in, or with login when not.

[doc/routing.md](doc/routing.md) explains routes in full.

## 4. The API client

Controllers depend on interfaces, and API clients implement them on top of `BaseApiClient`. `BaseApiClient` sends requests through boundary's `HttpService`, which adds the sign-in token, and turns failures into typed exceptions.

```dart
class CaseSummary {
  const CaseSummary({required this.id, required this.name});
  final int id;
  final String name;
}

abstract interface class CaseRepository {
  Future<List<CaseSummary>> list();
  Future<CaseSummary> get(int id);
}

class CaseApi extends BaseApiClient implements CaseRepository {
  CaseApi(super.httpService, super.config);

  static const _casesPath = 'api/cases';

  @override
  Future<List<CaseSummary>> list() {
    return performRequest(
      request: () => httpService.get(buildApiUri(_casesPath)),
      parser: (body) => [
        for (final item in jsonDecode(body) as List)
          CaseSummary(id: item['id'] as int, name: item['name'] as String),
      ],
      resourceName: 'Cases',
    );
  }

  @override
  Future<CaseSummary> get(int id) {
    return performRequest(
      request: () => httpService.get(buildApiUri('$_casesPath/$id')),
      parser: (body) {
        final item = jsonDecode(body) as Map<String, dynamic>;
        return CaseSummary(id: item['id'] as int, name: item['name'] as String);
      },
      resourceName: 'Case',
    );
  }
}
```

The login call is a client too. It sends `requireAuth: false`, because there is no token yet. A wrong password then comes back as a 401 that becomes `CredentialsRejectedException`.

```dart
class LoginCredentials {
  const LoginCredentials({required this.email, required this.password});
  final String email;
  final String password;
}

class AuthApi extends BaseApiClient {
  AuthApi(super.httpService, super.config);

  static const _loginPath = 'api/auth/login';

  Future<TokenGrant> login(LoginCredentials credentials) {
    return performRequest(
      request: () => httpService.post(
        buildApiUri(_loginPath),
        body: jsonEncode({
          'email': credentials.email,
          'password': credentials.password,
        }),
        requireAuth: false,
      ),
      parser: (body) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        return TokenGrant(
          token: json['token'] as String,
          subject: credentials.email,
        );
      },
      resourceName: 'Login',
    );
  }
}
```

[doc/api_client.md](doc/api_client.md) lists the exceptions and covers problem+json error bodies.

## 5. The login page

A controller holds a screen's logic. It takes actions in through `dispatch`, does the work in `handleAction`, and puts state on streams for the page. Everything it creates is registered with `own`, so it is released when the controller is disposed.

```dart
abstract final class LoginFormKeys {
  static const email = 'email';
  static const password = 'password';
}

sealed class LoginAction {}

final class SignIn extends LoginAction {}

class LoginController extends Controller<LoginAction> {
  LoginController(this._auth, this._errors);

  final StoredTokenAuthService<LoginCredentials> _auth;
  final ErrorPolicy _errors;

  late final form = own(FormGroup({
    LoginFormKeys.email: FormControl<String>(
      validators: [Validators.required, Validators.email],
    ),
    LoginFormKeys.password: FormControl<String>(
      validators: [Validators.required],
    ),
  }));

  late final _error = own(BehaviorSubject<String?>.seeded(null));
  late final _busy = own(BehaviorSubject<bool>.seeded(false));

  /// The sign-in error to show under the button, or null.
  ValueStream<String?> get error => _error.stream;
  ValueStream<bool> get busy => _busy.stream;

  @override
  Future<void> handleAction(LoginAction action) async {
    switch (action) {
      case SignIn():
        if (form.invalid) {
          form.markAllAsTouched();
          return;
        }
        emit(_busy, true);
        emit(_error, null);
        try {
          await _auth.signIn(LoginCredentials(
            email: form.control(LoginFormKeys.email).value as String,
            password: form.control(LoginFormKeys.password).value as String,
          ));
          // No navigateTo: the coordinator sees Authenticated and leaves
          // the guest-only login route by itself.
        } on CredentialsRejectedException catch (e) {
          emit(_error, _errors.messageFor(e));
        } finally {
          emit(_busy, false);
        }
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    _errors.handle(error, stackTrace);
  }
}
```

A refused password is shown inline, under the button. Any other error reaches `onError`, which passes it to the `ErrorPolicy`, and the policy shows it as a notice. The controller never navigates after signing in: the coordinator watches the auth state and moves on by itself.

The page only draws the controller's state and dispatches actions. It reads its controller with `context.read`:

```dart
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LoginController>();
    return Scaffold(
      body: ReactiveForm(
        formGroup: controller.form,
        child: Column(
          children: [
            ReactiveTextField<String>(formControlName: LoginFormKeys.email),
            ReactiveTextField<String>(
              formControlName: LoginFormKeys.password,
              obscureText: true,
            ),
            StreamBuilder<bool>(
              stream: controller.busy,
              initialData: controller.busy.value,
              builder: (context, busy) => FilledButton(
                onPressed:
                    busy.data! ? null : () => controller.dispatch(SignIn()),
                child: const Text('Sign in'),
              ),
            ),
            StreamBuilder<String?>(
              stream: controller.error,
              initialData: controller.error.value,
              builder: (context, error) => error.data == null
                  ? const SizedBox.shrink()
                  : Text(error.data!),
            ),
          ],
        ),
      ),
    );
  }
}
```

## 6. The cases list

The list controller loads in `enter`, which the coordinator calls once after it creates the controller. The data goes on an `AsyncResult` stream: `Loading`, then `Data` or `Failure`.

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

`emit` adds a value unless the controller is already disposed, so a slow load cannot throw after the user has left. Give `Loading` and `Failure` their type argument when you emit them. Without it Dart infers `<dynamic>`, and the stream throws at runtime.

The page shows the stream with `AsyncResultBuilder`:

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

## 7. One case

The case page reads the id from its route in `enter`, and goes back up to the list with `navigateUp()`, which follows the route's `parent`. Its `onError` sends errors to the error policy, which shows them as notices.

```dart
sealed class CaseAction {}

final class LoadCase extends CaseAction {
  LoadCase(this.id);
  final int id;
}

final class GoBack extends CaseAction {}

class CaseController extends Controller<CaseAction> {
  CaseController(this._cases, this._navigation, this._errors);

  final CaseRepository _cases;
  final NavigationService _navigation;
  final ErrorPolicy _errors;

  late final _detail = own(
    BehaviorSubject<AsyncResult<CaseSummary>>.seeded(const Loading()),
  );

  ValueStream<AsyncResult<CaseSummary>> get detail => _detail.stream;

  @override
  void enter(CaseRoute route) => dispatch(LoadCase(route.id));

  @override
  Future<void> handleAction(CaseAction action) async {
    switch (action) {
      case LoadCase(:final id):
        emit(_detail, Data(await _cases.get(id)));
      case GoBack():
        _navigation.navigateUp();
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    _errors.handle(error, stackTrace);
  }
}

class CasePage extends StatelessWidget {
  const CasePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<CaseController>();
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => controller.dispatch(GoBack()),
          ),
        ),
        AsyncResultBuilder<CaseSummary>(
          stream: controller.detail,
          data: (context, found) => Text(found.name),
        ),
      ],
    );
  }
}
```

## 8. A shared layout

The list and the case page share an app bar with a "Sign out" button. That frame is a layout, with its own controller. The layout controller lives as long as the pages that use it are shown.

```dart
enum ShellAction { signOut }

class ShellController extends Controller<ShellAction> {
  ShellController(this._auth);

  final AuthService _auth;

  @override
  Future<void> handleAction(ShellAction action) async {
    switch (action) {
      case ShellAction.signOut:
        // The coordinator sees SignedOut and shows the login route.
        await _auth.signOut();
    }
  }
}

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

final shell = LayoutBinding<ShellController>(
  controller: (i) => i.get<ShellController>(),
  builder: (child) => ShellLayout(child: child),
);
```

The pages inside the layout build no `Scaffold` of their own. The delegate registers `ShellController` in the next step.

## 9. The delegate

The delegate is your app's part of the coordinator. It registers your services, lists your routes, and names the login and home routes.

```dart
class SplashController extends Controller<Never> {
  @override
  void handleAction(Never action) {}
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class AppDelegate extends AppCoordinatorDelegate {
  @override
  void registerDependencies(AutoInjector injector) {
    injector.addInstance<AppConfig>(const AppConfigImpl());
    injector.addSingleton<AuthApi>(AuthApi.new);
    injector.addSingleton<CaseRepository>(CaseApi.new);

    final auth = StoredTokenAuthService<LoginCredentials>(
      login: (credentials) => injector.get<AuthApi>().login(credentials),
      store: SharedPreferencesCredentialStore(),
    );
    injector.addInstance<AuthService>(auth);
    injector.addInstance<StoredTokenAuthService<LoginCredentials>>(auth);

    // Controllers. `add` makes a new one each time a binding asks.
    injector.add(SplashController.new);
    injector.add(LoginController.new);
    injector.add(ShellController.new);
    injector.add(CasesController.new);
    injector.add(CaseController.new);
  }

  @override
  List<RouteBinding> get routes => [
        RouteBinding<RootRoute, SplashController>(
          path: RootRoute.path,
          parse: (_) => const RootRoute(),
          controller: (i) => i.get<SplashController>(),
          page: const SplashPage(),
        ),
        RouteBinding<LoginRoute, LoginController>(
          path: LoginRoute.path,
          parse: (_) => const LoginRoute(),
          controller: (i) => i.get<LoginController>(),
          page: const LoginPage(),
          access: RouteAccess.guestOnly,
        ),
        RouteBinding<CasesRoute, CasesController>(
          path: CasesRoute.path,
          parse: (_) => const CasesRoute(),
          controller: (i) => i.get<CasesController>(),
          page: const CasesPage(),
          layout: shell,
        ),
        RouteBinding<CaseRoute, CaseController>(
          path: CaseRoute.path,
          parse: (params) => CaseRoute(int.parse(params['id']!)),
          controller: (i) => i.get<CaseController>(),
          page: const CasePage(),
          layout: shell,
        ),
      ];

  @override
  List<RouteGuard> createGuards(AutoInjector injector) => const [];

  @override
  ConfigurationBase getLoginRoute() => const LoginRoute();

  @override
  ConfigurationBase getPostLoginDefaultRoute() => const CasesRoute();
}
```

A few things to notice:

- **Registrations.** The coordinator has already registered `NavigationService`, `ErrorPolicy`, `NoticeService` and `HttpService`. `HttpService` needs an `AuthService`, so you must register one. `BaseApiClient` needs the `AppConfig`.
- **The auth service** is registered twice: as `AuthService` for the framework, and as `StoredTokenAuthService` for the login controller. Its login call finds `AuthApi` in the injector only when it runs. That breaks the cycle `AuthApi` → `HttpService` → `AuthService`.
- **`SharedPreferencesCredentialStore` is not secure.** It stores the token in plain storage. Use it while developing, and supply a secure `CredentialStore` before you ship. See [doc/auth.md](doc/auth.md).
- **`access`.** Routes are `protected` unless the binding says otherwise. Login is `guestOnly`, so a signed-in user who opens it goes to the cases list.
- **Controllers are registered with `add`**, so each `get` makes a new one. The coordinator disposes a controller when its page goes, so never register a controller as a singleton. The injector fills each constructor's parameters by type, so a binding only asks for its controller with `i.get<T>()`. See [doc/architecture.md](doc/architecture.md), "Dependency injection".

## 10. main()

`main()` creates the coordinator and connects it to Flutter's router. `NoticeSnackBarListener` shows the error policy's notices as SnackBars.

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initializeCoreMappers();

  final coordinator = AppCoordinator(AppDelegate());
  final router = CoreRouterDelegate(
    appCoordinator: coordinator,
    pageBuilder: const AppPageBuilder(),
  );

  runApp(MaterialApp.router(
    title: 'Cases',
    routeInformationParser: AppRouteInformationParser(coordinator.routeTable),
    routerDelegate: router,
    builder: (context, child) => NoticeSnackBarListener(
      notices: coordinator.injector.get<NoticeService>().notices,
      child: child!,
    ),
  ));
}

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

- `initializeCoreMappers()` prepares the models boundary uses to read error bodies. Call it once, before any request.
- `AppPageBuilder` decides how each shown route becomes a Navigator page.

## 11. Run it

Start your backend and run the app. You should see:

1. The loading page for a moment, then the login page.
2. A wrong password shows "The sign-in details were not accepted." under the button.
3. After signing in, the cases list under the "Cases" app bar.
4. Tapping a case opens its page. The back arrow returns to the list.
5. "Sign out" returns to the login page. Restart the app after signing in again: it opens signed in, because the token was stored.

## Next steps

- Write tests for these controllers: [doc/testing.md](doc/testing.md).
- Add an auto-saving form to the case page: [doc/forms.md](doc/forms.md).
- Keep the case page when moving to another case, with `RouteUpdatable`: [doc/controllers.md](doc/controllers.md).
- Give part of a page its own controller: [doc/sub_controllers.md](doc/sub_controllers.md).
- Restrict a page by role with a guard: [doc/routing.md](doc/routing.md).
- Change how errors are shown: [doc/errors.md](doc/errors.md).
- Tell your app's agents about boundary: [doc/building_with_boundary.md](doc/building_with_boundary.md), last section.
