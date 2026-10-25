/// Formatters for dates, numbers and currency.
library;

import 'package:intl/intl.dart';

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
