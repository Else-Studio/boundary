/// Abstract class for application-specific configuration.
///
/// This contract is defined in the `boundary` framework and must be
/// implemented and provided by the host application (e.g., `vh_web`).
///
/// It centralizes environment-specific values like the API base URL
/// and application-wide settings like default debounce times.
abstract class AppConfig {
  /// The root URL for all API calls (e.g., 'http://localhost:8080').
  String get baseUrl;

  /// The public-web origin used when composing links returned by the backend.
  String get publicWebOrigin;

  /// The standard debounce time for UI interactions, like filter text fields.
  Duration get debounceTime;

  /// The duration of inactivity before the SSE connection is considered stale.
  Duration get sseWatchdogTimeout;

  /// The minimum delay to wait before retrying an SSE connection.
  Duration get sseMinRetryDelay;
}
