import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:talker/talker.dart';

export 'package:talker/talker.dart' show LogLevel;

// Configuration for Talker logger colors in light mode.
Map<String, AnsiPen> _talkerLight = {
  TalkerKey.verbose: AnsiPen()..white(),
  TalkerKey.debug: AnsiPen()..green(),
};

/// Lowest level every useLogger logger prints. Read each time a message is
/// logged, so it applies to loggers created earlier.
LogLevel boundaryLogLevel = LogLevel.verbose;

// Filters by [boundaryLogLevel], read at log time. A quiet logger also drops
// verbose and debug.
class _LevelFilter extends TalkerFilter {
  final bool quiet;
  _LevelFilter({required this.quiet});

  @override
  bool filter(TalkerData item) {
    final level = item.logLevel ?? LogLevel.info;
    if (quiet && (level == LogLevel.verbose || level == LogLevel.debug)) {
      return false;
    }
    return logLevelPriorityList.indexOf(level) <=
        logLevelPriorityList.indexOf(boundaryLogLevel);
  }
}

class CustomFormatter implements LoggerFormatter {
  final String module;
  const CustomFormatter(this.module);

  @override
  String fmt(LogDetails details, TalkerLoggerSettings settings) {
    final underline = ConsoleUtils.getUnderline(
      settings.maxLineWidth,
      lineSymbol: settings.lineSymbol,
    );

    final originalMessage = details.message;
    final RegExp pattern = RegExp(r'^(\s*\[[A-Z]\])(.*)$');
    String msg;

    if (originalMessage == null) {
      msg = '$module-no message';
    } else {
      final RegExpMatch? match = pattern.firstMatch(originalMessage);
      if (match != null) {
        final String matchedPrefix = match.group(1)!;
        final String restOfString = match.group(2)!;
        msg = '$matchedPrefix[$module]$restOfString';
      } else {
        msg = '$module-$originalMessage';
      }
    }

    if (!settings.enableColors) {
      return '$msg\n$underline';
    }
    var lines = msg.split('\n');
    lines = lines.map((e) => details.pen.write(e)).toList();

    // Only draw underline in debug mode
    if (!kReleaseMode) {
      lines.add(details.pen.write(underline));
    }
    final coloredMsg = lines.join('\n');
    return coloredMsg;
  }
}

/// Get a logger with a dedicated label. Keep it 4 letters long.
/// By default, logs will be "quiet" (verbose and debug suppressed) in release builds.
Talker useLogger(String label, {bool quiet = kReleaseMode}) => Talker(
      // Default 'quiet' to kReleaseMode
      settings: TalkerSettings(
        colors: _talkerLight,
        titles: {
          TalkerKey.verbose: 'V',
          TalkerKey.debug: 'D',
          TalkerKey.info: 'I',
          TalkerKey.warning: 'W',
          TalkerKey.error: 'E',
          TalkerKey.critical: 'C',
        },
      ),
      logger: TalkerLogger(
        formatter: CustomFormatter(label),
        settings: TalkerLoggerSettings(maxLineWidth: 25, lineSymbol: '.-'),
      ),
      filter: _LevelFilter(quiet: quiet),
    );

/// Global logger instance. Please don't use this if possible.
/// This logger will be quiet in release builds by default.
final Talker appLogger = useLogger('----');

/// Represents the state of an asynchronous operation, providing a type-safe
/// way to handle loading, success (with data), and error states.
sealed class AsyncResult<T> {
  const AsyncResult();

  T? get dataOrNull => this is Data<T> ? (this as Data<T>).data : null;
}

class Empty<T> extends AsyncResult<T> {
  const Empty();
}

class Loading<T> extends AsyncResult<T> {
  const Loading();
}

class Data<T> extends AsyncResult<T> {
  final T data;
  const Data(this.data);
}

class Failure<T> extends AsyncResult<T> {
  final Object error;
  final String? messageKey;
  final StackTrace? stackTrace;
  const Failure(this.error, {this.stackTrace, this.messageKey});

  @override
  String toString() => 'Failure($error, messageKey: $messageKey)';
}

/// A centralized class for handling date, number, and currency formatting.
/// These methods take a locale string directly to avoid dependency on BuildContext.
class AppFormatters {
  /// Formats a numeric value as a currency string.
  static String formatCurrency(
    num value,
    String locale, {
    required String symbol,
    int decimalDigits = 2,
  }) {
    return NumberFormat.currency(
      locale: locale,
      symbol: symbol,
      decimalDigits: decimalDigits,
    ).format(value);
  }

  /// Parses a string into a double using locale-agnostic logic.
  /// It identifies the last '.' or ',' as the decimal separator and ignores
  /// all other non-digit characters, making it robust against grouping separators
  /// or misplaced currency symbols.
  ///
  /// The [locale] parameter is ignored but kept for signature compatibility.
  /// Returns null if the string is empty or cannot be parsed.
  static double? parseLocalDouble(String? value, String locale) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    String sanitizedValue = value.trim();
    int lastDotIndex = sanitizedValue.lastIndexOf('.');
    int lastCommaIndex = sanitizedValue.lastIndexOf(',');

    int decimalSeparatorIndex = -1;

    if (lastDotIndex > lastCommaIndex) {
      decimalSeparatorIndex = lastDotIndex;
    } else if (lastCommaIndex > lastDotIndex) {
      decimalSeparatorIndex = lastCommaIndex;
    }

    final buffer = StringBuffer();
    for (int i = 0; i < sanitizedValue.length; i++) {
      final char = sanitizedValue[i];
      if (RegExp(r'[0-9]').hasMatch(char)) {
        buffer.write(char);
      } else if (i == 0 && char == '-') {
        // Allow a leading minus sign for negative numbers.
        buffer.write(char);
      } else if (i == decimalSeparatorIndex) {
        // Standardize the identified decimal separator to a period.
        buffer.write('.');
      }
      // Implicitly ignore all other characters (grouping separators, symbols, etc.)
    }

    return double.tryParse(buffer.toString());
  }

  /// Formats a number into a locale-specific decimal string (no currency symbol).
  static String formatLocalDecimal(num value, String locale) {
    return NumberFormat.decimalPattern(locale).format(value);
  }

  /// Returns a DateFormat instance for short date format (e.g., 12/31/2023).
  static DateFormat getShortDateFormat(String locale) {
    return DateFormat.yMd(locale);
  }

  /// Formats a DateTime object into a short date string (e.g., 12/31/2023).
  static String formatDateShort(DateTime date, String locale) {
    return getShortDateFormat(locale).format(date.toLocal());
  }

  /// Formats a DateTime object into a long date string (e.g., December 31, 2023).
  static String formatDateLong(DateTime date, String locale) {
    return DateFormat.yMMMMd(locale).format(date.toLocal());
  }

  /// Formats a DateTime object into a date and time string (e.g., 12/31/2023 11:59 PM).
  static String formatDateTime(DateTime date, String locale) {
    return DateFormat.yMd(locale).add_Hm().format(date.toLocal());
  }

  /// Formats a DateTime object into a time string (e.g., 11:59 PM).
  static String formatTime(DateTime date, String locale) {
    return DateFormat.Hm(locale).format(date.toLocal());
  }
}

/// A mixin to provide standardized URI building capabilities for API clients.
///
/// It separates the concern of constructing a valid endpoint `Uri` from the
/// actual HTTP request logic.
mixin ApiUriBuilder {
  /// The base URL for the API endpoints.
  /// This must be provided by the class using the mixin.
  String get apiBaseUrl;

  /// Constructs a `Uri` for a given API endpoint.
  ///
  /// It intelligently combines the base URL with the [relativePath] and
  /// optional [queryParameters], ensuring the final URL is well-formed.
  ///
  /// The base URL used will be [overrideBaseUrl] if provided, otherwise it
  /// defaults to the client's [apiBaseUrl].
  ///
  /// Null values in [queryParameters] are automatically filtered out.
  /// [Iterable] values are correctly expanded into multiple query parameters
  /// (e.g., `key=val1&key=val2`). All other values are converted to their
  /// string representation.
  Uri buildApiUri(
    String relativePath, {
    Map<String, dynamic>? queryParameters,
    String? overrideBaseUrl,
  }) {
    final baseUrl = overrideBaseUrl ?? apiBaseUrl;

    // Clean up path to avoid double slashes if the base URL has a trailing slash
    // and the relative path has a leading one.
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanPath =
        relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;

    final fullPath = '$cleanBase/$cleanPath';

    final uri = Uri.parse(fullPath).replace(
      queryParameters: (queryParameters?.isNotEmpty ?? false)
          ? queryParameters!.map((key, value) {
              if (value is Iterable) {
                return MapEntry(key, value.map((e) => e.toString()).toList());
              }
              return MapEntry(key, value.toString());
            })
          : null,
    );
    return uri;
  }
}
