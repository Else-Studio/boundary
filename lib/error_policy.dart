import 'notice.dart';
import 'router.dart';
import 'service/base_api_client.dart';
import 'service/navigation_service.dart';
import 'utils.dart';

class ErrorPolicy {
  ErrorPolicy(this.notices, this.navigation);

  final NoticeService notices;
  final NavigationService navigation;
  final _logger = useLogger('ErPo');

  /// English text for inline display. Override for other texts.
  String messageFor(Object error) {
    if (error is InvalidInputException) {
      final violations = error.validationProblem?.violations;
      if (violations != null) {
        final messages = violations
            .map((v) => v.message)
            .whereType<String>()
            .where((m) => m.isNotEmpty)
            .toList();
        if (messages.isNotEmpty) {
          return messages.join('\n');
        }
      }
      return error.message ?? error.toString();
    }
    if (error is NetworkException) {
      return 'Could not connect. Please check your network connection.';
    }
    if (error is DataParsingException) {
      return 'Something went wrong.';
    }
    if (error is ApiException) {
      return error.message ?? error.toString();
    }
    return 'Something went wrong.';
  }

  /// warning for RateLimitExceededException, error otherwise.
  NoticeLevel levelFor(Object error) {
    if (error is RateLimitExceededException) {
      return NoticeLevel.warning;
    }
    return NoticeLevel.error;
  }

  /// A page to show for [error]. Default: null for every error.
  ConfigurationBase? pageFor(Object error) => null;

  /// Triages [error] into a notice, a page, or nothing.
  void handle(Object error, [StackTrace? stackTrace]) {
    if (error is SessionTerminatedException) {
      _logger.info('Session terminated: $error');
      return;
    }

    if (error is ApiException) {
      _logger.warning('API error: $error', error, stackTrace);
    } else {
      _logger.error('Unhandled error: $error', error, stackTrace);
    }

    final page = pageFor(error);
    if (page != null) {
      navigation.navigateTo(page);
      return;
    }

    notices.show(Notice(messageFor(error), level: levelFor(error)));
  }
}
