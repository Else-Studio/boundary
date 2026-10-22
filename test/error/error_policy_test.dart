import 'dart:async';

import 'package:boundary/boundary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/mock_dependency_provider.dart';
import '../helpers/sut_factory.dart';

/// Maps [ForbiddenException] to an error page; every other error stays a notice.
class CasePolicy extends ErrorPolicy {
  CasePolicy(super.notices, super.navigation);

  @override
  ConfigurationBase? pageFor(Object error) {
    if (error is ForbiddenException) {
      return const ErrorRoute(message: 'forbidden');
    }
    return null;
  }
}

/// Sends action errors through [errorPolicy].
class PolicyController extends Controller<String> with PolicyErrors<String> {
  PolicyController(this.errorPolicy);

  @override
  final ErrorPolicy errorPolicy;

  @override
  FutureOr<void> handleAction(String action) async {
    await Future<void>.delayed(Duration.zero);
    throw NetworkException();
  }
}

/// Shows the policy's message on [inlineError] instead of posting a notice.
class InlineErrorController extends Controller<String>
    with PolicyErrors<String> {
  InlineErrorController(this.errorPolicy) {
    own(inlineError);
  }

  @override
  final ErrorPolicy errorPolicy;

  final BehaviorSubject<String?> inlineError = BehaviorSubject.seeded(null);

  @override
  void onError(Object error, StackTrace stackTrace) {
    inlineError.value = errorPolicy.messageFor(error);
  }

  @override
  FutureOr<void> handleAction(String action) {
    throw ForbiddenException();
  }
}

void main() {
  late MockDependencyProvider provider;
  late NoticeService notices;
  late ErrorPolicy policy;
  late List<Notice> received;

  setUp(() async {
    provider = MockDependencyProvider();
    await SutFactory.initTestBed(provider: provider);
    notices = SutFactory.createNoticeService();
    policy = SutFactory.createErrorPolicy(provider: provider, notices: notices);
    received = <Notice>[];
    final sub = notices.notices.listen(received.add);
    addTearDown(() async {
      try {
        await sub.cancel();
      } catch (_) {}
      try {
        notices.dispose();
      } catch (_) {}
    });
  });

  group('errors become notices with the policy text', () {
    test('a network exception becomes a connection notice', () {
      policy.handle(NetworkException());

      expect(received, [
        const Notice(
          'Could not connect. Please check your network connection.',
        ),
      ]);
      verifyNever(provider.mockNavigationService.navigateTo(any));
    });

    test(
        'a network exception with details still becomes a connection notice',
        () {
      policy.handle(
        NetworkException(
          details:
              'ClientNetworkException: SocketException: Failed host lookup',
        ),
      );

      expect(received, [
        const Notice(
          'Could not connect. Please check your network connection.',
        ),
      ]);
      verifyNever(provider.mockNavigationService.navigateTo(any));
    });

    test('a data parsing exception becomes a generic notice', () {
      policy.handle(
        DataParsingException('Bad JSON for Case: Unexpected character'),
      );

      expect(received, [const Notice('Something went wrong.')]);
      verifyNever(provider.mockNavigationService.navigateTo(any));
    });

    test('a rate limit exception becomes a warning notice', () {
      policy.handle(RateLimitExceededException());

      expect(received, [
        const Notice(
          'You are making too many requests. Please wait a moment and try again.',
          level: NoticeLevel.warning,
        ),
      ]);
      verifyNever(provider.mockNavigationService.navigateTo(any));
    });

    test('a forbidden exception becomes a permission notice', () {
      policy.handle(ForbiddenException());

      expect(received, [
        const Notice('You do not have permission to access this resource.'),
      ]);
      verifyNever(provider.mockNavigationService.navigateTo(any));
    });

    test('validation violations become a joined notice', () {
      policy.handle(
        InvalidInputException(
          'Invalid',
          validationProblem: HttpValidationProblem(
            violations: [
              Violation(field: 'name', message: 'Name is required.'),
              Violation(field: 'blank', message: ''),
              Violation(field: 'age', message: 'Age must be a number.'),
              Violation(field: 'missing'),
            ],
          ),
        ),
      );

      expect(received, [
        const Notice('Name is required.\nAge must be a number.'),
      ]);
      verifyNever(provider.mockNavigationService.navigateTo(any));
    });

    test('an invalid input without violations uses its message', () {
      policy.handle(
        InvalidInputException('Invalid input provided for Case.'),
      );

      expect(received, [
        const Notice('Invalid input provided for Case.'),
      ]);
      verifyNever(provider.mockNavigationService.navigateTo(any));
    });

    test('validation problems with no usable messages use the exception message',
        () {
      policy.handle(
        InvalidInputException(
          'Invalid input provided for Case.',
          validationProblem: HttpValidationProblem(
            violations: [
              Violation(field: 'blank', message: ''),
              Violation(field: 'missing'),
            ],
          ),
        ),
      );

      expect(received, [
        const Notice('Invalid input provided for Case.'),
      ]);
      verifyNever(provider.mockNavigationService.navigateTo(any));
    });

    test('rejected credentials become a sign-in notice', () {
      policy.handle(CredentialsRejectedException());

      expect(received, [
        const Notice('The sign-in details were not accepted.'),
      ]);
      verifyNever(provider.mockNavigationService.navigateTo(any));
    });

    test('an unknown error becomes a generic notice', () {
      policy.handle(StateError('boom'));

      expect(received, [const Notice('Something went wrong.')]);
      verifyNever(provider.mockNavigationService.navigateTo(any));
    });
  });

  test('a terminated session raises no notice and does not navigate', () {
    policy.handle(SessionTerminatedException());

    expect(received, isEmpty);
    verifyNever(provider.mockNavigationService.navigateTo(any));
  });

  group('an app can map an error to a page', () {
    late CasePolicy casePolicy;

    setUp(() {
      casePolicy = CasePolicy(notices, provider.mockNavigationService);
    });

    test('a mapped forbidden error navigates and posts no notice', () {
      casePolicy.handle(ForbiddenException());

      verify(
        provider.mockNavigationService.navigateTo(
          const ErrorRoute(message: 'forbidden'),
        ),
      ).called(1);
      expect(received, isEmpty);
    });

    test('an unmapped network error still becomes a notice', () {
      casePolicy.handle(NetworkException());

      expect(received, [
        const Notice(
          'Could not connect. Please check your network connection.',
        ),
      ]);
      verifyNever(provider.mockNavigationService.navigateTo(any));
    });
  });

  test('a controller with PolicyErrors sends its errors to notices', () async {
    final controller = PolicyController(policy);
    addTearDown(controller.dispose);

    controller.dispatch('go');
    await pumpEventQueue();

    expect(received, [
      const Notice(
        'Could not connect. Please check your network connection.',
      ),
    ]);
  });

  test('a controller can show an error inline instead of a notice', () async {
    final controller = InlineErrorController(policy);
    addTearDown(controller.dispose);

    controller.dispatch('go');
    await pumpEventQueue();

    expect(
      controller.inlineError.value,
      'You do not have permission to access this resource.',
    );
    expect(received, isEmpty);
  });
}
