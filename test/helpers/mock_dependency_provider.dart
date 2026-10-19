// ignore_for_file: depend_on_referenced_packages

import 'package:http/http.dart' as http;
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:boundary/service/auth_service.dart';
import 'package:boundary/utils.dart';

import 'mocks.mocks.dart';
import 'model_factory.dart';

// --- MockDependencyProvider Checklist ---
// 1. Generate the Mock: Ensure a mock class for the service exists.
// 2. Define the "Happy Path": Explicitly decide the service's default success state.
// 3. Stub the Public Interface: Stub all public members to reflect the happy path.
// 4. Keep Stubs Simple: Stubs must only return static data or simple Futures,
//    making them trivial to override for error-case testing.

/// A centralized provider for all mocked service dependencies.
///
/// It creates mock instances and configures them with default "happy path"
/// stubs, ensuring that the simplest tests require zero arrangement.
class MockDependencyProvider {
  late MockAuthService mockAuthService;
  late MockNavigationService mockNavigationService;
  late MockBaseClient mockHttpClient;
  late MockAppCoordinatorDelegate mockAppCoordinatorDelegate;
  late MockController mockController; // Add this

  MockDependencyProvider() {
    // 1. Create all mock instances
    mockAuthService = MockAuthService();
    mockNavigationService = MockNavigationService();
    mockHttpClient = MockBaseClient();
    mockAppCoordinatorDelegate = MockAppCoordinatorDelegate();
    mockController = MockController(); // And this

    // 2. Apply default "happy path" stubs
    _stubDefaults();
  }

  /// Sets up the default "happy path" stubs for all services.
  /// By default, all operations are instantly successful.
  void _stubDefaults() {
    // --- AuthService ---
    // The user is instantly and successfully authenticated.
    when(mockAuthService.authenticated).thenReturn(true);
    when(mockAuthService.userStream).thenAnswer(
      (_) => BehaviorSubject.seeded(Data(ModelFactory.createUser())),
    );

    // --- NavigationService ---
    // Navigation calls complete successfully but do nothing.
    when(mockNavigationService.navigateTo(any)).thenAnswer((_) async {});
    when(mockNavigationService.consumePostAuthRedirect())
        .thenAnswer((_) async => null);

    // --- HttpClient ---
    // By default, all requests are successful with an empty JSON body.
    when(mockHttpClient.get(any, headers: anyNamed('headers')))
        .thenAnswer((_) async => http.Response('{}', 200));
    when(mockHttpClient.post(any,
            headers: anyNamed('headers'), body: anyNamed('body')))
        .thenAnswer((_) async => http.Response('{}', 200));
    when(mockHttpClient.put(any,
            headers: anyNamed('headers'), body: anyNamed('body')))
        .thenAnswer((_) async => http.Response('{}', 200));
    when(mockHttpClient.delete(any,
            headers: anyNamed('headers'), body: anyNamed('body')))
        .thenAnswer((_) async => http.Response('{}', 200));

    // --- AppCoordinatorDelegate ---
    // By default, the delegate does not override any core logic.
    when(mockAppCoordinatorDelegate.resolveAppSpecificAuthState(any, any))
        .thenReturn(null);
    when(mockAppCoordinatorDelegate.routes).thenReturn([]);
    when(mockAppCoordinatorDelegate.isPublicOnlyRoute(any)).thenReturn(false);
    when(mockAppCoordinatorDelegate.isLogoutRoute(any)).thenReturn(false);
    when(mockAppCoordinatorDelegate.shouldDisposeController(any))
        .thenReturn(true);

    // --- SharedPreferences ---
    // A valid, empty SharedPreferences instance is available by default.
    stubSharedPreferences({});
  }

  // --- On-Demand Stubs for Specific Scenarios ---

  /// Overrides the default `userStream` stub to simulate a realistic
  /// asynchronous authentication flow (`Loading` state followed by `Data` state).
  ///
  /// Use this in tests that need to verify a controller's behavior
  /// during the authentication process.
  void stubAuthLoadingSequence() {
    when(mockAuthService.userStream).thenAnswer(
      (_) => Stream<AsyncResult<User>>.fromIterable([
        const Loading(),
        Data(ModelFactory.createUser()),
      ]).shareValueSeeded(const Loading()),
    );
  }

  /// Sets up an in-memory SharedPreferences instance with the given values.
  ///
  /// This uses the official testing package for shared_preferences to replace
  /// the platform-specific implementation with a simple in-memory map.
  void stubSharedPreferences(Map<String, Object> initialValues) {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(initialValues);
  }
}
