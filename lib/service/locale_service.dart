import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils.dart'; // For logger
import 'locale_changer.dart' if (dart.library.html) 'html_locale_changer.dart';

// Not wired: locale choice and persistence belong to the app. Playrecord does not switch languages. Kept as a reference.

/// Manages the application's current locale state.
class LocaleService {
  final _logger = useLogger('LoCS');
  static const String kLocaleStorageKey = 'app_locale';

  // Default locale if none is provided or detected initially.
  static const Locale defaultLocale = Locale('de');

  // Supported locales within the application.
  final List<Locale> supportedLocales = const [
    Locale('de'), // German
    Locale('en'), // English
  ];

  /// BehaviorSubject holding the current application locale.
  /// Seeded with the default locale initially.
  late final BehaviorSubject<Locale> _localeController;

  /// Stream providing the current application locale.
  ValueStream<Locale> get localeStream => _localeController.stream;

  /// Gets the current locale value directly.
  Locale get currentLocale => _localeController.value;

  LocaleService() {
    // Initialize with default and load from storage asynchronously.
    _localeController = BehaviorSubject<Locale>.seeded(defaultLocale);
    _loadLocaleFromStorage();
    _logger.info('LocaleService initialized.');

    _localeController.stream.distinct().listen((locale) {
      setBrowserLang(locale.toString());
    });
  }

  Future<void> _loadLocaleFromStorage() async {
    try {
      final prefs = SharedPreferencesAsync();
      final savedLanguageCode = await prefs.getString(kLocaleStorageKey);
      if (savedLanguageCode != null) {
        final locale = Locale(savedLanguageCode);
        if (supportedLocales.contains(locale)) {
          if (locale != _localeController.value) {
            _localeController.add(locale);
            _logger.info('Loaded locale from storage: $locale');
          }
        } else {
          _logger.warning(
            'Saved locale "$savedLanguageCode" is not supported. Using default.',
          );
        }
      } else {
        _logger.info('No locale found in storage. Using default.');
      }
    } catch (e, s) {
      _logger.error('Error loading locale from SharedPreferences', e, s);
    }
  }

  Future<void> _saveLocaleToStorage(Locale locale) async {
    try {
      final prefs = SharedPreferencesAsync();
      await prefs.setString(kLocaleStorageKey, locale.languageCode);
      _logger.info('Saved locale to storage: $locale');
    } catch (e, s) {
      _logger.error('Error saving locale to SharedPreferences', e, s);
    }
  }

  /// Sets the application's locale to the new [locale].
  ///
  /// This updates the internal state and notifies listeners via the [localeStream].
  /// The `MaterialApp` should listen to this stream to rebuild with the new locale.
  void setLocale(Locale locale) {
    // Ensure the locale is supported before setting
    if (supportedLocales.contains(locale)) {
      if (locale != _localeController.value) {
        _logger.info('Setting locale to: $locale');
        _localeController.add(locale);
        _saveLocaleToStorage(locale);
      } else {
        _logger.verbose('Locale $locale is already active.');
      }
    } else {
      _logger.warning(
        'Attempted to set unsupported locale: $locale. Ignoring.',
      );
    }
  }

  /// Disposes the stream controller when the service is no longer needed.
  void dispose() {
    _logger.info('Disposing LocaleService.');
    _localeController.close();
  }
}
