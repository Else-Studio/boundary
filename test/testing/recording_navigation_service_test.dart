import 'package:boundary/boundary.dart';
import 'package:boundary/testing.dart';
import 'package:flutter_test/flutter_test.dart' hide pumpEventQueue;

import '../helpers/sut_factory.dart';

class _A extends ConfigurationBase {
  static const String path = '/a';

  const _A();

  @override
  String get pathTemplate => path;
}

class _B extends ConfigurationBase {
  static const String path = '/b';

  const _B();

  @override
  String get pathTemplate => path;
}

class _Login extends ConfigurationBase {
  static const String path = '/login';

  const _Login();

  @override
  String get pathTemplate => path;
}

class _Home extends ConfigurationBase {
  static const String path = '/home';

  const _Home();

  @override
  String get pathTemplate => path;
}

class _VetoingGuard implements LeaveGuard {
  const _VetoingGuard();

  @override
  bool get hasUnsavedChanges => false;

  @override
  Future<bool> mayLeave() async => false;
}

void main() {
  RecordingNavigationService service() =>
      SutFactory.createRecordingNavigationService(
        loginRoute: const _Login(),
        homeRoute: const _Home(),
      );

  group('recording', () {
    test('every request is recorded in order', () async {
      final navigation = service();
      addTearDown(navigation.dispose);

      navigation.navigateTo(const _A());
      navigation.navigateTo(const _B());
      navigation.navigateBackOrLogin();
      await pumpEventQueue();

      expect(navigation.requests, [const _A(), const _B(), const _B()]);
    });

    test('back with nothing shown falls back to the login route', () async {
      final navigation = service();
      addTearDown(navigation.dispose);

      navigation.navigateBackOrLogin();
      await pumpEventQueue();

      expect(navigation.requests, [const _Login()]);
    });

    test('showing a route is not a request', () {
      final navigation = service();
      addTearDown(navigation.dispose);

      navigation.show(const _A());

      expect(navigation.requests, isEmpty);
    });
  });

  group('leave guards', () {
    test('a vetoing guard keeps the recording empty', () async {
      final navigation = service();
      addTearDown(navigation.dispose);
      navigation.show(const _A());
      navigation.addLeaveGuard(const _VetoingGuard());

      navigation.navigateTo(const _B());
      await pumpEventQueue();

      expect(navigation.requests, isEmpty);
    });
  });
}
