/// Abstract class for application-specific configuration.
///
/// This contract is defined in the `boundary` framework and must be
/// implemented and provided by the host application.
///
/// It centralizes environment-specific values like the API base URL
/// and application-wide settings like default debounce times.
abstract class AppConfig {
  /// The root URL for all API calls (e.g., 'http://localhost:8080').
  String get baseUrl;

  /// The standard debounce time for UI interactions, like filter text fields.
  Duration get debounceTime;
}
