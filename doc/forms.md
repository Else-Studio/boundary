# Forms

Boundary's forms are reactive_forms `FormGroup`s. For a form that saves as the user types, wrap the group in a `FormSession` from `package:boundary/forms.dart`. The session saves after a pause in typing, never runs two saves at once, reports its status, takes server updates without overwriting the user's edits, and puts server validation errors on the right fields. A `FormLeaveGuard` stops the user from losing unsaved changes by navigating away.

A form with a submit button, like a sign-in form, does not need a session. Own the `FormGroup` in the controller and read its value in the submit action.

## An auto-saving form

The controller owns the session, exposes the form and the status, and registers a leave guard:

```dart
abstract final class NoteFormKeys {
  static const note = 'note';
}

class NoteController extends Controller<NoteAction> {
  NoteController(
    this._cases,
    this._config,
    this._errors,
    NavigationService navigation,
    Dialogs dialogs,
  ) {
    own(navigation.addLeaveGuard(
      FormLeaveGuard(_session, confirm: dialogs.confirmDiscard),
    ));
  }

  final CaseRepository _cases;
  final AppConfig _config;
  final ErrorPolicy _errors;

  int? _caseId;

  late final _session = own(FormSession(
    form: FormGroup({
      NoteFormKeys.note: FormControl<String>(
        validators: [Validators.required],
      ),
    }),
    save: (value) => _cases.saveNote(
      _caseId!,
      value[NoteFormKeys.note]! as String,
    ),
    debounce: _config.debounceTime,
    onSaveError: _errors.handle,
  ));

  FormGroup get form => _session.form;
  ValueStream<SaveStatus> get status => _session.status;

  @override
  Future<void> handleAction(NoteAction action) async {
    switch (action) {
      case LoadNote(:final caseId):
        _caseId = caseId;
        final note = await _cases.note(caseId);
        _session.patchFromServer({NoteFormKeys.note: note});
      case RetrySave():
        await _session.retry();
    }
  }
}
```

The view binds the form and shows the status:

```dart
class NoteEditor extends StatelessWidget {
  const NoteEditor({super.key});

  @override
  Widget build(BuildContext context) {
    final note = context.read<NoteController>();
    return ReactiveForm(
      formGroup: note.form,
      child: Column(
        children: [
          ReactiveTextField<String>(formControlName: NoteFormKeys.note),
          StreamBuilder<SaveStatus>(
            stream: note.status,
            initialData: note.status.value,
            builder: (context, status) => Text(status.data!.name),
          ),
        ],
      ),
    );
  }
}
```

`FormSession` takes:

| Argument | Meaning |
|---|---|
| `form` | The `FormGroup`. It should start pristine. The session owns it and disposes it. |
| `save` | Saves the whole form value. Throw to report a failure. |
| `debounce` | How long to wait after the last edit. Use `AppConfig.debounceTime`. |
| `onSaveError` | Called with each failed save's error. Pass `ErrorPolicy.handle` to show a notice. The default logs it. |

Do not expose the session itself to the view. Its `flush` and `retry` are work, so the view reaches them through actions like `RetrySave`.

## The save cycle

`status` is a `ValueStream<SaveStatus>`. It starts at `idle` and emits only on change. The statuses are `idle`, `dirty`, `invalid`, `saving`, `saved` and `error`.

| Situation | What the session does |
|---|---|
| The user edits and the form is valid | Status `dirty`. Saves after `debounce` with no further edits. |
| The user edits and the form is invalid | Status `invalid`. Does not save. |
| The save starts | Status `saving`. |
| The save succeeds | Marks the form pristine. Status `saved`. |
| The user edits during a save | Saves exactly once more with the latest value, after the running save ends. |
| The save fails | Status `error`. Calls `onSaveError`. Does not retry by itself. |
| The save fails with `InvalidInputException` carrying violations | Puts the violations on their fields first, then status `error`. |
| The user edits after a failed save | Schedules a save as usual. |
| `retry()` | In `error` only: saves the current value now, if it is valid. |
| `flush()` | Saves now if the form is dirty and valid, and completes when the form is idle. Returns true if everything is saved, false if the form is invalid or the save failed. |
| `patchFromServer(value)` | Never saves. See below. |

`hasUnsavedChanges` is true while the status is `dirty`, `invalid`, `saving` or `error`. It is also true right after a user edit, before the session has seen the edit's event.

## What counts as an edit

The session saves only edits the user made. A user edit is a value change on a dirty control. The reactive_forms widgets mark a control dirty and then set its value, so typing in a field counts.

Setting a value in code, such as `control.value = 'x'`, leaves the control pristine, so the session does not save it. This is what you want when you fill the form from the server: no lock or flag is needed to stop a save loop. If code must change a value as if the user had typed it, call `control.markAsDirty()` first.

## Filling the form from the server

`patchFromServer(value)` writes server data into the form:

- It updates only pristine controls. A control the user is editing keeps the user's value.
- It marks the patched controls pristine.
- It never triggers a save.
- It goes into nested `FormGroup`s by key.

Use it for the first load, and whenever newer server data arrives, for example after another device saved.

## Server validation errors

When `save` throws an `InvalidInputException` whose problem has violations, the session sets each violation on its control before it reports the error. The error key is `server` and its value is the violation's message. The control is marked touched, so the message shows at once. Show it with the field's `validationMessages`:

```dart
ReactiveTextField<String>(
  formControlName: NoteFormKeys.note,
  validationMessages: {
    ValidationMessage.required: (_) => 'Write a note.',
    // Set by FormSession from the server's violations.
    'server': (error) => error as String,
  },
),
```

A violation's `field` is looked up with `form.findControl`, so it can name a nested control. You can also call `applyViolations(problem)` yourself, for example after a separate submit call. It returns the violations that matched no control, so you can show those elsewhere.

## Warning before leaving

`FormLeaveGuard(session, confirm: ...)` is a `LeaveGuard` for a form session. When the user navigates away:

1. If there are no unsaved changes, the user leaves.
2. Otherwise it calls `flush()`. If everything saves, the user leaves.
3. If the form is invalid or the save failed, it calls `confirm()`. The user leaves when `confirm` returns true.

Register it on `NavigationService` and own the registration, as the controller above does. [routing.md](routing.md), "Leave guards", lists when leave guards run.

`confirm` usually shows a dialog. A controller has no `BuildContext`, so give it a small service that opens dialogs on the router's navigator:

```dart
/// Dialogs a controller can ask for. The context comes from the router's
/// navigator key, read when a dialog opens.
class Dialogs {
  Dialogs(this._context);

  final BuildContext? Function() _context;

  Future<bool> confirmDiscard() async {
    final context = _context();
    if (context == null) return false;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }
}
```

Register it in `registerDependencies` with the context getter that `main()` passes to the delegate: `injector.addInstance<Dialogs>(Dialogs(dialogContext))`. [routing.md](routing.md), "Setting up the router", shows where `dialogContext` comes from.

## One form per selected item

When the form belongs to an item that can change while the page stays, such as the note of the shown case, put the form in a child controller held by a slot. Switching to another item creates a new child with a fresh session and disposes the old one. The leave guard runs before the switch, so unsaved changes are saved or confirmed first. See [sub_controllers.md](sub_controllers.md).

## Testing forms

Simulate a user edit the way a widget makes one: mark the control dirty, then set its value. Setting the value alone is not saved. Wait for the real debounce, with a short `debounceTime` in the test config. [testing.md](testing.md), "Forms", has the helper and examples.
