import 'package:boundary/boundary.dart';
import 'package:boundary/forms.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/form_fixture.dart';
import '../helpers/sut_factory.dart';

class _FormRouteA extends ConfigurationBase {
  static const String path = '/a';

  const _FormRouteA();

  @override
  String get pathTemplate => path;
}

class _FormRouteB extends ConfigurationBase {
  static const String path = '/b';

  const _FormRouteB();

  @override
  String get pathTemplate => path;
}

class _NoopController extends Controller<void> {
  @override
  void handleAction(void action) {}
}

class _LoginDelegate implements NavigationServiceDelegate {
  @override
  ConfigurationBase getLoginRoute() => const _FormRouteA();

  @override
  ConfigurationBase getPostLoginDefaultRoute() => const _FormRouteA();
}

void main() {
  const debounce = Duration(milliseconds: 50);

  late FormFixture fixture;
  late FormSession session;
  late List<int> confirmCalls;
  late bool confirmAnswer;
  late FormLeaveGuard guard;

  FormLeaveGuard createGuard() {
    return SutFactory.createFormLeaveGuard(
      session: session,
      confirm: () async {
        confirmCalls.add(confirmCalls.length + 1);
        return confirmAnswer;
      },
    );
  }

  setUp(() {
    fixture = FormFixture();
    confirmCalls = <int>[];
    confirmAnswer = true;
    session = SutFactory.createFormSession(
      form: fixture.form,
      save: fixture.save,
      debounce: debounce,
    );
    guard = createGuard();
  });

  tearDown(() {
    try {
      session.dispose();
    } catch (_) {}
  });

  test('a pristine form may leave without confirming', () async {
    expect(session.status.value, SaveStatus.idle);
    expect(guard.hasUnsavedChanges, isFalse);

    final result = await guard.mayLeave();

    expect(result, isTrue);
    expect(confirmCalls, isEmpty);
    expect(fixture.saves, isEmpty);
  });

  test('a dirty valid form flushes before leaving without confirming', () async {
    fixture.edit('title', 'A');
    expect(guard.hasUnsavedChanges, isTrue);

    final leaving = guard.mayLeave();
    await pumpEventQueue();

    expect(fixture.saves, hasLength(1));
    expect(fixture.saves.single['title'], 'A');

    await fixture.completeSave(0);
    expect(await leaving, isTrue);
    expect(confirmCalls, isEmpty);
  });

  test('an invalid form asks confirm and may leave when confirmed', () async {
    confirmAnswer = true;
    fixture.edit('title', '');
    expect(guard.hasUnsavedChanges, isTrue);

    final result = await guard.mayLeave();

    expect(result, isTrue);
    expect(confirmCalls, hasLength(1));
    expect(fixture.saves, isEmpty);
  });

  test('an invalid form asks confirm and stays when declined', () async {
    confirmAnswer = false;
    fixture.edit('title', '');

    final result = await guard.mayLeave();

    expect(result, isFalse);
    expect(confirmCalls, hasLength(1));
    expect(fixture.saves, isEmpty);
  });

  test('a failed flush asks confirm and uses that answer', () async {
    confirmAnswer = false;
    fixture.edit('title', 'A');

    final leaving = guard.mayLeave();
    await pumpEventQueue();
    expect(fixture.saves, hasLength(1));

    await fixture.failSave(0, StateError('down'));
    expect(await leaving, isFalse);
    expect(confirmCalls, hasLength(1));
  });

  test(
      'a dirty invalid form blocks navigation when the user declines to leave',
      () async {
    final service = NavigationService(
      delegate: _LoginDelegate(),
      routes: RouteTable([
        RouteBinding<_FormRouteA, _NoopController>(
          path: _FormRouteA.path,
          parse: (_) => const _FormRouteA(),
          controller: (_) => _NoopController(),
          page: const SizedBox.shrink(),
          access: RouteAccess.public,
        ),
        RouteBinding<_FormRouteB, _NoopController>(
          path: _FormRouteB.path,
          parse: (_) => const _FormRouteB(),
          controller: (_) => _NoopController(),
          page: const SizedBox.shrink(),
          access: RouteAccess.public,
        ),
      ]),
    );
    addTearDown(service.dispose);

    service.navigateTo(const _FormRouteA());
    service.onRouteResolved(base: const _FormRouteA(), modal: null);
    service.addLeaveGuard(
      SutFactory.createFormLeaveGuard(
        session: session,
        confirm: () async => false,
      ),
    );

    fixture.edit('title', '');
    service.navigateTo(const _FormRouteB());
    await pumpEventQueue();

    expect(service.currentRequestedConfiguration, const _FormRouteA());
  });
}
