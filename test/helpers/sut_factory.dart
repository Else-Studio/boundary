// ignore_for_file: deprecated_member_use_from_same_package

import 'package:auto_injector/auto_injector.dart';
import 'package:boundary/app_coordinator.dart';
import 'package:boundary/error_policy.dart';
import 'package:boundary/forms.dart';
import 'package:boundary/model/error_models.dart';
import 'package:boundary/notice.dart';
import 'package:boundary/oauth.dart';
import 'package:boundary/service/auth_service.dart';
import 'package:boundary/service/http_service.dart';
import 'package:boundary/service/locale_service.dart';
import 'package:boundary/service/navigation_service.dart';
import 'package:boundary/service/stored_token_auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:reactive_forms/reactive_forms.dart';

import 'mock_dependency_provider.dart';

// --- SutFactory Checklist ---
// 1. Single Instantiation Point: It must be the only place where a class is
//    instantiated for tests (with AppCoordinator being the only exception).
// 2. Use Static Methods: Implement a unique `static create...()` method for
//    each class under test.
// 3. Inject Dependencies via Provider: The factory method must use
//    MockDependencyProvider to inject all required dependencies.
// 4. Allow Overrides: The `create...()` method must accept an optional
//    MockDependencyProvider instance.

/// A factory for creating instances of classes under test (SUTs).
/// This is the single source of truth for test instantiation, ensuring
/// that constructor changes only require updates in this one file.
class SutFactory {
  /// Prepares the testing environment for SUT creation.
  ///
  /// This method handles any asynchronous setup required before tests are run,
  /// such as initializing in-memory stores like SharedPreferences. It should
  /// be called in the `setUp` function of a test file.
  static Future<void> initTestBed({MockDependencyProvider? provider}) async {
    // Ensure a provider exists and its defaults (including SharedPreferences)
    // are initialized. This makes the setup explicit.
    final effectiveProvider = provider ?? MockDependencyProvider();
    effectiveProvider.stubSharedPreferences({});

    initializeCoreMappers();
  }

  /// Creates a standard [LocaleService] instance.
  static LocaleService createLocaleService() {
    return LocaleService();
  }

  /// Creates an [HttpService] instance with its dependencies resolved.
  ///
  /// By default, it uses a mock [AuthService] as the token provider.
  /// A custom [MockDependencyProvider] can be passed in to override
  /// the default mock behavior for specific test cases.
  static HttpService createHttpService({MockDependencyProvider? provider}) {
    final effectiveProvider = provider ?? MockDependencyProvider();
    return HttpService(
      effectiveProvider.mockAuthService,
      effectiveProvider.mockHttpClient,
    );
  }

  /// Creates a [StoredTokenAuthService] around the given fakes.
  static StoredTokenAuthService<C> createStoredTokenAuthService<C>({
    required Future<TokenGrant> Function(C credentials) login,
    required CredentialStore store,
    Future<void> Function(String token)? logout,
  }) {
    return StoredTokenAuthService<C>(
      login: login,
      store: store,
      logout: logout,
    );
  }

  /// Creates an [OAuthAuthService] with the given config and test doubles.
  static OAuthAuthService createOAuthAuthService({
    required OAuthConfig config,
    http.Client? httpClient,
    TokenVerifier? verifier,
  }) {
    return OAuthAuthService(
      config,
      httpClient: httpClient,
      verifier: verifier,
    );
  }

  /// Creates a [SharedPreferencesPostAuthRedirectStore] with a test clock.
  static SharedPreferencesPostAuthRedirectStore
      createSharedPreferencesRedirectStore({
    DateTime Function()? now,
  }) {
    return SharedPreferencesPostAuthRedirectStore(now: now);
  }

  /// Creates a real [NoticeService].
  static NoticeService createNoticeService() => NoticeService();

  /// Creates an [ErrorPolicy] with a real [NoticeService] and the provider's
  /// mock navigation service. Pass [notices] to share the same instance the
  /// test listens on.
  static ErrorPolicy createErrorPolicy({
    MockDependencyProvider? provider,
    NoticeService? notices,
  }) {
    final effectiveProvider = provider ?? MockDependencyProvider();
    return ErrorPolicy(
      notices ?? createNoticeService(),
      effectiveProvider.mockNavigationService,
    );
  }

  static AppCoordinator createAppCoordinator(
      {MockDependencyProvider? provider}) {
    final effectiveProvider = provider ?? MockDependencyProvider();
    final injector = AutoInjector();

    // Hide the DI setup here
    injector.addSingleton<AuthService>(() => effectiveProvider.mockAuthService);
    injector.addSingleton<NavigationService>(
        () => effectiveProvider.mockNavigationService);
    injector.commit();

    return AppCoordinator(
      effectiveProvider.mockAppCoordinatorDelegate,
      injector: injector,
    );
  }

  /// Creates a [FormSession] around the given form and save callback.
  static FormSession createFormSession({
    required FormGroup form,
    required Future<void> Function(Map<String, Object?> value) save,
    required Duration debounce,
    void Function(Object error, StackTrace stackTrace)? onSaveError,
  }) {
    return FormSession(
      form: form,
      save: save,
      debounce: debounce,
      onSaveError: onSaveError,
    );
  }
}
