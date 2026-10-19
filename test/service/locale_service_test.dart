import 'package:boundary/service/locale_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mock_dependency_provider.dart';
import '../helpers/sut_factory.dart';

// --- Test Plan: LocaleService ---
//
// ## Group: Initialization
// - test('should initialize with the stored locale when one is available and supported')
// - test('should initialize with the default locale when the stored locale is unsupported')
// - test('should initialize with the default locale when no locale is stored')
// - test('should initialize with the default locale when storage throws an error')
//
// ## Group: setLocale
// - test('should update currentLocale and save to storage when a new supported locale is set')
// - test('should emit the new locale on localeStream when a new supported locale is set')
// - test('should do nothing when an unsupported locale is set')
// - test('should do nothing when the currently active locale is set again')
//
// ## Group: dispose
// - test('should close the localeStream when dispose is called')

void main() {
  late MockDependencyProvider provider;

  setUp(() async {
    // Arrange: Prepare the mock environment before each test.
    // This ensures a clean, isolated in-memory SharedPreferences instance.
    provider = MockDependencyProvider();
    await SutFactory.initTestBed(provider: provider);
  });

  group('LocaleService', () {
    group('Initialization', () {
      test(
          'should initialize with the stored locale when one is available and supported',
          () async {
        // Arrange: Use the public constant from the service to avoid magic strings.
        provider.stubSharedPreferences({LocaleService.kLocaleStorageKey: 'en'});
        final sut = SutFactory.createLocaleService();

        // Act: Wait for the asynchronous _loadLocaleFromStorage method,
        // which is called in the constructor, to complete.
        await Future.delayed(Duration.zero);

        // Assert: The service's current locale should now be the one from storage.
        expect(sut.currentLocale, const Locale('en'));
        expect(sut.localeStream, emits(const Locale('en')));
      });

      test(
          'should initialize with the default locale when the stored locale is unsupported',
          () async {
        // Arrange
        provider.stubSharedPreferences({LocaleService.kLocaleStorageKey: 'fr'});
        final sut = SutFactory.createLocaleService();

        // Act
        await Future.delayed(Duration.zero);

        // Assert: The service should ignore the unsupported locale and keep the default.
        expect(sut.currentLocale, LocaleService.defaultLocale);
      });

      test('should initialize with the default locale when no locale is stored',
          () async {
        // Arrange: The default setup provides no stored locale.
        final sut = SutFactory.createLocaleService();

        // Act
        await Future.delayed(Duration.zero);

        // Assert
        expect(sut.currentLocale, LocaleService.defaultLocale);
      });
    });

    group('setLocale', () {
      test(
          'should update currentLocale and save to storage when a new supported locale is set',
          () async {
        // Arrange
        final sut = SutFactory.createLocaleService();

        // Act
        sut.setLocale(const Locale('en'));
        // Wait for the async save operation to complete.
        await Future.delayed(Duration.zero);

        // Assert
        expect(sut.currentLocale, const Locale('en'));
        final prefs = SharedPreferencesAsync();
        expect(await prefs.getString(LocaleService.kLocaleStorageKey), 'en');
      });

      test(
          'should emit the new locale on localeStream when a new supported locale is set',
          () {
        // Arrange
        final sut = SutFactory.createLocaleService();

        // Act
        sut.setLocale(const Locale('en'));

        // Assert
        expect(sut.localeStream, emits(const Locale('en')));
      });

      test('should do nothing when an unsupported locale is set', () async {
        // Arrange
        final sut = SutFactory.createLocaleService();

        // Act
        sut.setLocale(const Locale('fr'));
        await Future.delayed(Duration.zero);

        // Assert: Locale should remain the default and nothing should be saved.
        expect(sut.currentLocale, LocaleService.defaultLocale);
        final prefs = SharedPreferencesAsync();
        expect(await prefs.getString(LocaleService.kLocaleStorageKey), isNull);
      });

      test('should do nothing when the currently active locale is set again',
          () async {
        // Arrange
        final sut = SutFactory.createLocaleService(); // Starts with 'de'

        // Act: Attempt to set the same locale
        sut.setLocale(const Locale('de'));
        await Future.delayed(Duration.zero);

        // Assert: The value should be the same and no save should have occurred.
        expect(sut.currentLocale, LocaleService.defaultLocale);
        final prefs = SharedPreferencesAsync();
        expect(await prefs.getString(LocaleService.kLocaleStorageKey), isNull);
      });
    });
  });
}
