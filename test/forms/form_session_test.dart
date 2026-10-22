import 'package:boundary/forms.dart';
import 'package:boundary/model/error_models.dart';
import 'package:boundary/service/base_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactive_forms/reactive_forms.dart';

import '../helpers/form_fixture.dart';
import '../helpers/sut_factory.dart';

void main() {
  const debounce = Duration(milliseconds: 50);

  late FormFixture fixture;
  late List<SaveStatus> statuses;
  late List<Object> errors;
  late FormSession session;

  FormSession createSession({Duration? debounceTime}) {
    return SutFactory.createFormSession(
      form: fixture.form,
      save: fixture.save,
      debounce: debounceTime ?? debounce,
      onSaveError: (error, stackTrace) => errors.add(error),
    );
  }

  setUp(() {
    fixture = FormFixture();
    statuses = <SaveStatus>[];
    errors = <Object>[];
    session = createSession();
    session.status.listen(statuses.add);
  });

  tearDown(() {
    try {
      session.dispose();
    } catch (_) {}
  });

  test('a valid edit saves once after the debounce', () async {
    expect(session.form, isA<FormGroup>());
    expect(session.status.value, SaveStatus.idle);
    expect(session.hasUnsavedChanges, isFalse);

    fixture.edit('title', 'New');
    expect(session.hasUnsavedChanges, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fixture.saves, isEmpty);
    expect(session.status.value, SaveStatus.dirty);
    expect(session.hasUnsavedChanges, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture.saves, [
      {
        'title': 'New',
        'notes': '',
        'address': {'city': ''},
      },
    ]);
    expect(session.status.value, SaveStatus.saving);

    await fixture.completeSave(0);
    expect(session.status.value, SaveStatus.saved);
    expect(fixture.form.pristine, isTrue);
    expect(session.hasUnsavedChanges, isFalse);
    expect(statuses, [
      SaveStatus.idle,
      SaveStatus.dirty,
      SaveStatus.saving,
      SaveStatus.saved,
    ]);
  });

  test('edits restart the debounce', () async {
    try {
      session.dispose();
    } catch (_) {}
    statuses = <SaveStatus>[];
    session = createSession(debounceTime: const Duration(milliseconds: 200));
    session.status.listen(statuses.add);

    fixture.edit('title', 'A');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    fixture.edit('title', 'B');

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(fixture.saves, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(fixture.saves, hasLength(1));
    expect(fixture.saves.single['title'], 'B');
  });

  test('an invalid form is not saved', () async {
    fixture.edit('title', '');
    expect(session.status.value, SaveStatus.invalid);
    expect(session.hasUnsavedChanges, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(fixture.saves, isEmpty);
  });

  test('edits during a save give exactly one follow-up with the latest value',
      () async {
    fixture.edit('title', 'A');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture.saves, hasLength(1));

    fixture.edit('title', 'B');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    fixture.edit('title', 'C');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture.saves, hasLength(1));

    await fixture.completeSave(0);
    expect(fixture.saves, hasLength(2));
    expect(fixture.saves[1]['title'], 'C');

    await fixture.completeSave(1);
    expect(session.status.value, SaveStatus.saved);
    expect(fixture.form.pristine, isTrue);
  });

  test('a failed save waits for retry', () async {
    fixture.edit('title', 'A');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture.saves, hasLength(1));

    await fixture.failSave(0, StateError('down'));
    expect(session.status.value, SaveStatus.error);
    expect(errors, hasLength(1));
    expect(errors.single, isA<StateError>());
    expect((errors.single as StateError).message, 'down');

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(fixture.saves, hasLength(1));
    expect(session.hasUnsavedChanges, isTrue);

    final retrying = session.retry();
    expect(fixture.saves, hasLength(2));
    expect(fixture.saves[1]['title'], 'A');

    await fixture.completeSave(1);
    await retrying;
    expect(session.status.value, SaveStatus.saved);
  });

  test('an edit after a failure schedules a save', () async {
    fixture.edit('title', 'A');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture.saves, hasLength(1));
    await fixture.failSave(0, StateError('down'));
    expect(session.status.value, SaveStatus.error);

    fixture.edit('title', 'B');
    expect(session.status.value, SaveStatus.dirty);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture.saves, hasLength(2));
    expect(fixture.saves[1]['title'], 'B');
  });

  test('violations from a failed save land on the controls', () async {
    fixture.edit('title', 'A');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture.saves, hasLength(1));

    final exception = InvalidInputException(
      'Invalid',
      validationProblem: const HttpValidationProblem(
        violations: [Violation(field: 'title', message: 'Taken.')],
      ),
    );
    await fixture.failSave(0, exception);

    expect(fixture.form.control('title').errors, {'server': 'Taken.'});
    expect(fixture.form.control('title').touched, isTrue);
    expect(session.status.value, SaveStatus.error);
    expect(errors, [exception]);

    fixture.edit('notes', 'x');
    expect(session.status.value, SaveStatus.invalid);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture.saves, hasLength(1));

    fixture.edit('title', 'Other');
    expect(fixture.form.control('title').errors.containsKey('server'), isFalse);
    expect(session.status.value, SaveStatus.dirty);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture.saves, hasLength(2));
    expect(fixture.saves[1]['title'], 'Other');
  });

  test('applyViolations maps fields and returns the rest', () async {
    final unmatched = session.applyViolations(
      const HttpValidationProblem(
        violations: [
          Violation(field: 'title', message: 'Required.'),
          Violation(field: 'address.city', message: 'Unknown city.'),
          Violation(field: 'nope', message: 'X'),
          Violation(message: 'General.'),
        ],
      ),
    );

    expect(unmatched, [
      const Violation(field: 'nope', message: 'X'),
      const Violation(message: 'General.'),
    ]);
    expect(fixture.form.control('title').errors, {'server': 'Required.'});
    expect(
      fixture.form.control('address.city').errors,
      {'server': 'Unknown city.'},
    );
    expect(fixture.form.pristine, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture.saves, isEmpty);

    final other = FormFixture();
    final otherSession = SutFactory.createFormSession(
      form: other.form,
      save: other.save,
      debounce: debounce,
    );
    addTearDown(() {
      try {
        otherSession.dispose();
      } catch (_) {}
    });
    final none =
        otherSession.applyViolations(const HttpProblem(title: 'Conflict'));
    expect(none, isEmpty);
    expect(other.form.control('title').errors, isEmpty);
    expect(other.form.control('notes').errors, isEmpty);
    expect(other.form.control('address.city').errors, isEmpty);
  });

  test('a server patch on a pristine form does not save', () async {
    session.patchFromServer({
      'title': 'Server',
      'address': {'city': 'Ipoh'},
    });

    expect(fixture.form.control('title').value, 'Server');
    expect(fixture.form.control('address.city').value, 'Ipoh');
    expect(fixture.form.control('title').pristine, isTrue);
    expect(fixture.form.control('address.city').pristine, isTrue);
    expect(session.status.value, SaveStatus.idle);

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(fixture.saves, isEmpty);
  });

  test('a server patch skips what the user is editing', () async {
    fixture.edit('notes', 'Mine');
    session.patchFromServer({'title': 'Server', 'notes': 'Theirs'});

    expect(fixture.form.control('title').value, 'Server');
    expect(fixture.form.control('title').pristine, isTrue);
    expect(fixture.form.control('notes').value, 'Mine');
    expect(fixture.form.control('notes').dirty, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fixture.saves, [
      {
        'title': 'Server',
        'notes': 'Mine',
        'address': {'city': ''},
      },
    ]);
  });

  test('flush saves a dirty form now', () async {
    fixture.edit('title', 'A');
    final flushed = session.flush();

    await pumpEventQueue();
    expect(fixture.saves, hasLength(1));

    await fixture.completeSave(0);
    expect(await flushed, isTrue);
    expect(session.status.value, SaveStatus.saved);

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(fixture.saves, hasLength(1));
  });

  group('flush in the other states', () {
    test('flush on idle returns true with no save', () async {
      expect(await session.flush(), isTrue);
      expect(fixture.saves, isEmpty);
    });

    test('flush on invalid returns false with no save', () async {
      fixture.edit('title', '');
      expect(await session.flush(), isFalse);
      expect(fixture.saves, isEmpty);
    });

    test('flush on error returns false and leaves the failed save', () async {
      fixture.edit('title', 'A');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(fixture.saves, hasLength(1));
      await fixture.failSave(0, StateError('down'));
      expect(session.status.value, SaveStatus.error);

      expect(await session.flush(), isFalse);
      expect(fixture.saves, hasLength(1));
    });

    test('flush while saving waits for that save and returns true', () async {
      fixture.edit('title', 'A');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(fixture.saves, hasLength(1));

      final flushed = session.flush();
      await fixture.completeSave(0);
      expect(await flushed, isTrue);
      expect(fixture.saves, hasLength(1));
    });

    test(
        'flush while saving with a later edit starts the follow-up at once',
        () async {
      fixture.edit('title', 'A');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(fixture.saves, hasLength(1));

      fixture.edit('title', 'B');
      final flushed = session.flush();
      await fixture.completeSave(0);
      expect(fixture.saves, hasLength(2));
      expect(fixture.saves[1]['title'], 'B');

      await fixture.completeSave(1);
      expect(await flushed, isTrue);
      expect(fixture.saves, hasLength(2));
    });

    test('flush while saving then invalid returns false', () async {
      fixture.edit('title', 'A');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(fixture.saves, hasLength(1));

      fixture.edit('title', '');
      final flushed = session.flush();
      await fixture.completeSave(0);
      expect(await flushed, isFalse);
      expect(session.status.value, SaveStatus.invalid);
      expect(fixture.saves, hasLength(1));
    });
  });

  test('dispose stops everything', () async {
    fixture.edit('title', 'A');
    session.dispose();

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(fixture.saves, isEmpty);

    await expectLater(
      session.status,
      emitsInOrder([anything, emitsDone]),
    );
    await expectLater(fixture.form.valueChanges, emitsDone);

    final fixture2 = FormFixture();
    final session2 = SutFactory.createFormSession(
      form: fixture2.form,
      save: fixture2.save,
      debounce: debounce,
      onSaveError: (error, stackTrace) => errors.add(error),
    );

    fixture2.edit('title', 'A');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture2.saves, hasLength(1));
    final flushed = session2.flush();
    session2.dispose();
    expect(await flushed, isFalse);
    await fixture2.completeSave(0);
    expect(await session2.flush(), isFalse);
  });

  test('a server patch during a save queues no follow-up', () async {
    fixture.edit('title', 'A');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture.saves, hasLength(1));

    session.patchFromServer({'notes': 'Theirs'});
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fixture.form.control('notes').value, 'Theirs');
    expect(session.status.value, SaveStatus.saving);

    await fixture.completeSave(0);
    expect(session.status.value, SaveStatus.saved);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(fixture.saves, hasLength(1));
  });

  group('how a save ends when edits came during it', () {
    test('edits pending with the timer still running go to dirty', () async {
      fixture.edit('title', 'A');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(fixture.saves, hasLength(1));

      fixture.edit('title', 'B');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await fixture.completeSave(0);
      expect(session.status.value, SaveStatus.dirty);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(fixture.saves, hasLength(2));
      expect(fixture.saves[1]['title'], 'B');
    });

    test('the form becoming invalid goes to invalid with no follow-up',
        () async {
      fixture.edit('title', 'A');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(fixture.saves, hasLength(1));

      fixture.edit('title', '');
      await fixture.completeSave(0);
      expect(session.status.value, SaveStatus.invalid);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(fixture.saves, hasLength(1));
    });

    test('a failed save with a follow-up queued drops the follow-up', () async {
      fixture.edit('title', 'A');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(fixture.saves, hasLength(1));

      fixture.edit('title', 'B');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await fixture.failSave(0, StateError('down'));
      expect(session.status.value, SaveStatus.error);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(fixture.saves, hasLength(1));

      session.retry();
      expect(fixture.saves, hasLength(2));
      expect(fixture.saves[1]['title'], 'B');
    });
  });
}
