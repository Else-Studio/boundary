import 'dart:async';

import 'package:reactive_forms/reactive_forms.dart';
import 'package:rxdart/rxdart.dart';

import '../disposable.dart';
import '../model/error_models.dart';
import '../service/base_api_client.dart';
import '../utils.dart';

/// Status of a [FormSession]'s auto-save cycle.
enum SaveStatus { idle, dirty, invalid, saving, saved, error }

/// Wraps a reactive_forms [FormGroup] with debounced auto-save, server
/// patching, and violation mapping.
class FormSession implements Disposable {
  /// [form] should start pristine. The session owns it and disposes it.
  FormSession({
    required FormGroup form,
    required Future<void> Function(Map<String, Object?> value) save,
    required Duration debounce,
    void Function(Object error, StackTrace stackTrace)? onSaveError,
  })  : _form = form,
        _save = save,
        _debounce = debounce,
        _onSaveError = onSaveError ?? _defaultOnSaveError,
        _status = BehaviorSubject.seeded(SaveStatus.idle) {
    _lastSeen = _cloneMap(form.value);
    _valueSubscription = form.valueChanges.listen((_) => _onFormValue());
  }

  final FormGroup _form;
  final Future<void> Function(Map<String, Object?> value) _save;
  final Duration _debounce;
  final void Function(Object error, StackTrace stackTrace) _onSaveError;
  final BehaviorSubject<SaveStatus> _status;

  late Map<String, Object?> _lastSeen;
  StreamSubscription<Map<String, Object?>?>? _valueSubscription;
  Timer? _debounceTimer;
  bool _disposed = false;
  bool _saveRunning = false;
  bool _userEditSinceSaveStarted = false;
  bool _followUpQueued = false;
  final List<Completer<bool>> _flushWaiters = [];

  /// The form, for the reactive_forms widgets.
  FormGroup get form => _form;

  /// Starts at idle; emits only on change.
  ///
  /// Access pulls a user edit whose value event has not arrived yet, so
  /// [value] matches [form.dirty] / validity at once.
  ValueStream<SaveStatus> get status {
    _pullPendingUserEdit();
    return _status;
  }

  /// dirty, invalid, saving or error. Also true right after a user edit,
  /// before its value event has arrived (it reads form.dirty).
  bool get hasUnsavedChanges {
    if (_disposed) return false;
    return _form.dirty;
  }

  /// Counts a user edit made just before the call, even if its value event
  /// has not arrived yet. Completes when no save is running or pending.
  Future<bool> flush() async {
    if (_disposed) return false;
    await Future<void>.delayed(Duration.zero);
    if (_disposed) return false;
    _pullPendingUserEdit();

    final current = _status.value;
    if (current == SaveStatus.idle || current == SaveStatus.saved) {
      return true;
    }
    if (current == SaveStatus.invalid || current == SaveStatus.error) {
      return false;
    }
    if (current == SaveStatus.dirty) {
      _cancelTimer();
      final waited = _addFlushWaiter();
      await _startSave();
      return waited;
    }

    // saving
    if (_userEditSinceSaveStarted) {
      _cancelTimer();
      if (_form.valid) {
        _followUpQueued = true;
      } else {
        _followUpQueued = false;
      }
    }
    return _addFlushWaiter();
  }

  /// Only in error: saves the current value now (if valid).
  Future<void> retry() async {
    if (_disposed) return;
    _pullPendingUserEdit();
    if (_status.value != SaveStatus.error) return;
    if (_form.invalid) return;
    await _startSave();
  }

  /// Patches pristine controls from the server. Never schedules a save.
  void patchFromServer(Map<String, Object?> value) {
    if (_disposed) return;
    _pullPendingUserEdit();
    _patchGroup(_form, value);
  }

  /// Maps [HttpValidationProblem] violations onto controls; returns the rest.
  List<Violation> applyViolations(HttpProblem problem) {
    if (_disposed) return const [];
    if (problem is! HttpValidationProblem) return const [];

    final unmatched = <Violation>[];
    for (final violation in problem.violations) {
      final field = violation.field;
      if (field == null || field.isEmpty) {
        unmatched.add(violation);
        continue;
      }
      final control = _form.findControl(field);
      if (control == null) {
        unmatched.add(violation);
        continue;
      }
      control.setErrors(
        {'server': violation.message ?? ''},
        markAsDirty: false,
      );
      control.markAsTouched();
    }
    return unmatched;
  }

  /// Cancels a pending save, completes pending flushes with false, closes
  /// status, disposes form. Idempotent.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelTimer();
    _followUpQueued = false;
    _valueSubscription?.cancel();
    _valueSubscription = null;
    for (final waiter in _flushWaiters) {
      if (!waiter.isCompleted) waiter.complete(false);
    }
    _flushWaiters.clear();
    if (!_status.isClosed) {
      _status.close();
    }
    _form.dispose();
  }

  static void _defaultOnSaveError(Object error, StackTrace stackTrace) {
    appLogger.error(
      'FormSession save failed: $error',
      error,
      stackTrace,
    );
  }

  void _onFormValue() {
    if (_disposed) return;
    final current = _cloneMap(_form.value);
    final userEdit = _isUserEdit(_lastSeen, current);
    _lastSeen = current;
    if (userEdit) {
      _handleUserEdit();
    }
  }

  /// Applies a user edit whose value is already on the form but whose
  /// valueChanges event has not been delivered yet.
  void _pullPendingUserEdit() {
    if (_disposed) return;
    final current = _cloneMap(_form.value);
    if (!_isUserEdit(_lastSeen, current)) return;
    _lastSeen = current;
    _handleUserEdit();
  }

  void _handleUserEdit() {
    if (_disposed) return;

    if (_saveRunning) {
      _userEditSinceSaveStarted = true;
      if (_form.invalid) {
        _cancelTimer();
        _followUpQueued = false;
      } else {
        _restartTimer();
      }
      return;
    }

    if (_form.invalid) {
      _cancelTimer();
      _setStatus(SaveStatus.invalid);
      _notifyFlushWaiters();
      return;
    }

    _setStatus(SaveStatus.dirty);
    _restartTimer();
  }

  void _restartTimer() {
    _cancelTimer();
    _debounceTimer = Timer(_debounce, _onDebounceFired);
  }

  void _cancelTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  void _onDebounceFired() {
    _debounceTimer = null;
    if (_disposed) return;
    if (_saveRunning) {
      _followUpQueued = true;
      return;
    }
    if (_form.invalid || !_form.dirty) return;
    unawaited(_startSave());
  }

  Future<void> _startSave() async {
    if (_disposed || _saveRunning) return;
    if (_form.invalid) {
      _setStatus(SaveStatus.invalid);
      _notifyFlushWaiters();
      return;
    }

    _saveRunning = true;
    _setStatus(SaveStatus.saving);

    while (!_disposed) {
      _userEditSinceSaveStarted = false;
      _followUpQueued = false;
      final value = _cloneMap(_form.value);

      try {
        await _save(value);
      } catch (e, s) {
        if (_disposed) break;
        _saveRunning = false;
        _handleSaveError(e, s);
        return;
      }

      if (_disposed) break;

      if (_followUpQueued) {
        if (_form.invalid) {
          _saveRunning = false;
          _setStatus(SaveStatus.invalid);
          _notifyFlushWaiters();
          return;
        }
        continue;
      }

      if (_userEditSinceSaveStarted) {
        _saveRunning = false;
        if (_form.invalid) {
          _cancelTimer();
          _setStatus(SaveStatus.invalid);
        } else {
          _setStatus(SaveStatus.dirty);
          if (!(_debounceTimer?.isActive ?? false)) {
            _restartTimer();
          }
        }
        _notifyFlushWaiters();
        return;
      }

      _saveRunning = false;
      _form.markAsPristine();
      _setStatus(SaveStatus.saved);
      _notifyFlushWaiters();
      return;
    }

    _saveRunning = false;
  }

  void _handleSaveError(Object error, StackTrace stackTrace) {
    _cancelTimer();
    _followUpQueued = false;
    if (error is InvalidInputException) {
      final problem = error.validationProblem;
      if (problem != null) {
        applyViolations(problem);
      }
    }
    _setStatus(SaveStatus.error);
    _onSaveError(error, stackTrace);
    _notifyFlushWaiters();
  }

  void _setStatus(SaveStatus next) {
    if (_disposed || _status.isClosed) return;
    if (_status.value == next) return;
    _status.add(next);
  }

  Future<bool> _addFlushWaiter() {
    if (_disposed) return Future<bool>.value(false);
    final completer = Completer<bool>();
    _flushWaiters.add(completer);
    _notifyFlushWaiters();
    return completer.future;
  }

  void _notifyFlushWaiters() {
    if (_flushWaiters.isEmpty) return;
    if (_disposed) {
      for (final waiter in _flushWaiters) {
        if (!waiter.isCompleted) waiter.complete(false);
      }
      _flushWaiters.clear();
      return;
    }
    if (_saveRunning || _followUpQueued) return;
    if (_debounceTimer?.isActive ?? false) return;
    final current = _status.value;
    if (current == SaveStatus.dirty || current == SaveStatus.saving) return;

    final ok = current == SaveStatus.saved || current == SaveStatus.idle;
    for (final waiter in _flushWaiters) {
      if (!waiter.isCompleted) waiter.complete(ok);
    }
    _flushWaiters.clear();
  }

  void _patchGroup(FormGroup group, Map<String, Object?> value) {
    for (final entry in value.entries) {
      final control = group.controls[entry.key];
      if (control == null) continue;
      final childValue = entry.value;
      if (control is FormGroup && childValue is Map) {
        _patchGroup(
          control,
          Map<String, Object?>.from(childValue),
        );
      } else if (control.dirty) {
        continue;
      } else {
        control.updateValue(childValue);
        control.markAsPristine();
      }
    }
  }

  bool _isUserEdit(Map<String, Object?> before, Map<String, Object?> after) {
    return _anyDirtyLeafChange(_form, before, after);
  }

  bool _anyDirtyLeafChange(
    FormGroup group,
    Map<String, Object?> before,
    Map<String, Object?> after,
  ) {
    final keys = <String>{...before.keys, ...after.keys};
    for (final key in keys) {
      final control = group.controls[key];
      if (control == null) continue;
      final oldValue = before[key];
      final newValue = after[key];
      if (control is FormGroup) {
        final oldMap = oldValue is Map
            ? Map<String, Object?>.from(oldValue)
            : <String, Object?>{};
        final newMap = newValue is Map
            ? Map<String, Object?>.from(newValue)
            : <String, Object?>{};
        if (_anyDirtyLeafChange(control, oldMap, newMap)) return true;
      } else if (oldValue != newValue && control.dirty) {
        return true;
      }
    }
    return false;
  }

  Map<String, Object?> _cloneMap(Map<String, Object?>? value) {
    if (value == null) return <String, Object?>{};
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key: entry.value is Map
            ? _cloneMap(Map<String, Object?>.from(entry.value! as Map))
            : entry.value,
    };
  }
}
