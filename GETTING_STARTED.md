# Getting Started with Boundary

This guide walks you through the initial setup of a new Flutter application using the Boundary framework. By the end, you will have a minimal, runnable app with a login page and a home page, structured according to Boundary's core architectural patterns.

---

## Prerequisites

Before you begin, ensure you have the following installed:

* Flutter SDK
* An IDE like VS Code or Android Studio
* A new, empty Flutter project created with `flutter create my_app`

---

## Step 1: Project Configuration

The Boundary framework relies on external configuration for authentication details. We will set this up using a `.env` file.

### 1. Add Dependencies

Add the following packages to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  # Add Boundary framework dependencies
  auto_injector: ^1.1.0
  provider: ^6.1.2
  rxdart: ^0.28.0
  dart_mappable: ^4.2.2
  oauth2: ^2.0.2
  shared_preferences: ^2.2.3
  talker: ^4.1.3
  http: ^1.2.1
  flutter_dotenv: ^5.1.0

dev_dependencies:
  # Add build_runner and mappers for code generation
  build_runner: ^2.4.9
  dart_mappable_builder: ^4.2.2
```

Then, run `flutter pub get`.

### 2\. Create the .env File

In the root directory of your project, create a file named `.env`. This file will store your authentication credentials and endpoints.

```
CLIENT_ID=your_client_id
CLIENT_SCOPES=scope1,scope2
AUTHORIZATION_ENDPOINT=https://auth.server.com/auth
TOKEN_ENDPOINT=https://auth.server.com/token
PUBLICKEY_ENDPOINT=https://auth.server.com/keys
LOGOUT_ENDPOINT=https://auth.server.com/logout
REDIRECT_URL=http://localhost:8080/callback.html
LOGOUT_REDIRECT_URL=http://localhost:8080/logout-callback.html
```

### 3\. Update pubspec.yaml

To make the `.env` file accessible to your app, declare it as an asset in `pubspec.yaml`:

```yaml
flutter:
  uses-material-design: true
  assets:
    - .env
```

### 4\. Load Environment Variables

Modify your `lib/main.dart` to be asynchronous and load the variables before the app starts.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  // Load the environment variables
  await dotenv.load(fileName: '.env');

  runApp(const MyApp());
}

// ... rest of the file
```

-----

## Step 2: Define Application Routes

Create classes for each destination in your app. This provides type-safe navigation.

**Create file:** `lib/routes.dart`

```dart
import 'package:boundary/router.dart';

class LoginRoute extends ConfigurationBase {
  static const String pathTemplate = '/login';
  const LoginRoute() : super(isProtected: false);
  @override
  Uri get uri => Uri.parse(pathTemplate);
  static ConfigurationBase create(Map<String, String> params) => const LoginRoute();
}

class HomeRoute extends ConfigurationBase {
  static const String pathTemplate = '/';
  const HomeRoute();
  @override
  Uri get uri => Uri.parse(pathTemplate);
  static ConfigurationBase create(Map<String, String> params) => const HomeRoute();
}

final Map<RegExp, ConfigurationBuilder> routeMap = {
  pathToRegExp(LoginRoute.pathTemplate): LoginRoute.create,
  pathToRegExp(HomeRoute.pathTemplate): HomeRoute.create,
};
```

-----

## Step 3: Implement Core Services

You need to provide concrete implementations for the framework's abstract `AuthService` and `ApiClient`.

### 1\. Create AuthService Implementation

**Create file:** `lib/my_app_auth_service.dart`

```dart
import 'package:boundary/service/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyAppAuthService extends BaseAuthService {
  MyAppAuthService(super.localeService) : super(loggerLabel: 'ApAS');

  @override
  Future<AuthError?> performPreAuthenticationChecks(SharedPreferences prefs) async {
    // For now, we have no special checks, so we return null to indicate success.
    return null;
  }
  
  @override
  Future<void> acceptDataPolicy() {
    throw UnimplementedError();
  }
}
```

### 2\. Create ApiClient

**Create file:** `lib/api_client.dart`

```dart
import 'package:boundary/service/base_api_client.dart';
import 'package:boundary/service/http_service.dart';

abstract class ApiClient {
  // Define methods for your API calls here.
}

class LiveApiClient extends BaseApiClient implements ApiClient {
  LiveApiClient(HttpService httpService) : super(httpService);
  // Implement ApiClient methods here.
}
```

-----

## Step 4: Create the AppCoordinatorDelegate

This class is the bridge between the framework and your application code.

**Create file:** `lib/my_app_coordinator_delegate.dart`

```dart
import 'package:auto_injector/auto_injector.dart';
import 'package:boundary/app_coordinator_delegate.dart';
import 'package:boundary/controller.dart';
import 'package:boundary/router.dart';
import 'package:boundary/utils.dart';
import 'package:boundary/service/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'routes.dart';
import 'login/login.dart';
import 'home/home.dart';
import 'api_client.dart';
import 'my_app_auth_service.dart';

class MyAppCoordinatorDelegate extends AppCoordinatorDelegate {
  @override
  void registerDependencies(AutoInjector injector) {
    injector.addSingleton<AuthService>(MyAppAuthService.new);
    injector.addSingleton<ApiClient>(LiveApiClient.new);
    injector.add(LoginController.new);
    injector.add(HomeController.new);
  }

  @override
  Controller createControllerForConfiguration(
    ConfigurationBase configuration, AutoInjector injector) {
    return switch (configuration) {
      LoginRoute() => injector.get<LoginController>(),
      HomeRoute() => injector.get<HomeController>(),
      _ => throw UnimplementedError('No controller for ${configuration.runtimeType}'),
    };
  }

  @override
  Widget mapControllerToWidget(Controller controller) {
    return switch (controller) {
      LoginController() => Provider<LoginController>.value(
          value: controller,
          child: const LoginPage(),
        ),
      HomeController() => Provider<HomeController>.value(
          value: controller,
          child: const HomePage(),
        ),
      _ => throw UnimplementedError('No widget for ${controller.runtimeType}'),
    };
  }
  
  @override
  ConfigurationBase getLoginRoute() => const LoginRoute();

  @override
  ConfigurationBase getPostLoginDefaultRoute() => const HomeRoute();

  @override
  bool isPublicOnlyRoute(ConfigurationBase config) => config is LoginRoute;

  @override
  bool isLogoutRoute(ConfigurationBase config) => false;
  
  @override
  ConfigurationBase? parseUri(Uri uri) => null;

  @override
  ConfigurationBase? resolveAppSpecificAuthState(
    AsyncResult<User> authState, ConfigurationBase navRequest) => null;

  @override
  bool shouldDisposeController(Controller? controller) => true;

  @override
  ConfigurationBase getResetPasswordRoute({String? email}) => throw UnimplementedError();
}
```

-----

## Step 5: Build Features

Create the Controller and Page for your initial features. You can combine them in one file for simplicity.

**Create file:** `lib/login/login.dart`

```dart
import 'package:boundary/controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

sealed class LoginAction {}
class LoginButtonPressed extends LoginAction {}

class LoginController extends Controller<LoginAction> {
  @override
  void handleAction(LoginAction action) {
    switch (action) {
      case LoginButtonPressed():
        print("Login button was pressed!");
    }
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = context.read<LoginController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => controller.dispatch(LoginButtonPressed()),
          child: const Text('Log In'),
        ),
      ),
    );
  }
}
```

**Create file:** `lib/home/home.dart`

```dart
import 'package:boundary/controller.dart';
import 'package:flutter/material.dart';

sealed class HomeAction {}

class HomeController extends Controller<HomeAction> {
  @override
  void handleAction(HomeAction action) {}
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: const Center(
        child: Text('Welcome! You are logged in.'),
      ),
    );
  }
}
```

-----

## Step 6: Finalize main.dart

Update your main file to initialize and run the framework with all the components you've built.

**Replace the content of:** `lib/main.dart`

```dart
import 'package:boundary/app_coordinator.dart';
import 'package:boundary/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'my_app_coordinator_delegate.dart';
import 'routes.dart';

void main() async {
  await dotenv.load(fileName: '.env');
  runApp(const MyApp());
}

class AppPageBuilder extends RouterPageBuilder {
  @override
  Page buildBasePage(
    BuildContext context, ConfigurationBase config, Widget contentWidget) {
    return NoAnimationPage(
      key: ValueKey(config.uri.path),
      child: contentWidget,
    );
  }

  @override
  Page buildModalPage(
    BuildContext context, ConfigurationBase config, Widget contentWidget) {
    return TransparentModalPage(
      key: ValueKey(config.uri.path),
      child: contentWidget,
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppCoordinator _appCoordinator;
  late final CoreRouterDelegate _routerDelegate;
  late final AppRouteInformationParser _routeInformationParser;

  @override
  void initState() {
    super.initState();
    final delegate = MyAppCoordinatorDelegate();
    _appCoordinator = AppCoordinator(delegate);
    _routerDelegate = CoreRouterDelegate(
      appCoordinator: _appCoordinator,
      pageBuilder: AppPageBuilder(),
    );
    _routeInformationParser = AppRouteInformationParser(
      routeMap: routeMap,
      defaultRoute: const LoginRoute(),
    );
  }

  @override
  void dispose() {
    _appCoordinator.dispose();
    _routerDelegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appCoordinator,
      child: MaterialApp.router(
        title: 'Boundary App',
        routerDelegate: _routerDelegate,
        routeInformationParser: _routeInformationParser,
      ),
    );
  }
}
```
