import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reactive_forms/reactive_forms.dart';

/// Shared form + save-callback fixture for [FormSession] tests.
class FormFixture {
  FormFixture()
      : form = FormGroup({
          'title': FormControl<String>(
            value: 'Old',
            validators: [Validators.required],
          ),
          'notes': FormControl<String>(value: ''),
          'address': FormGroup({
            'city': FormControl<String>(value: ''),
          }),
        });

  final FormGroup form;
  final List<Map<String, Object?>> saves = [];
  final List<Completer<void>> _completers = [];

  /// A user edit the way a reactive_forms widget makes one.
  void edit(String path, Object? value) {
    form.control(path)
      ..markAsDirty(emitEvent: false)
      ..value = value;
  }

  /// Save callback for the session. Each call records [value] and returns a
  /// fresh completer future.
  Future<void> save(Map<String, Object?> value) {
    saves.add({
      for (final entry in value.entries)
        entry.key: entry.value is Map
            ? Map<String, Object?>.from(entry.value! as Map)
            : entry.value,
    });
    final completer = Completer<void>();
    _completers.add(completer);
    return completer.future;
  }

  Future<void> completeSave(int i) async {
    _completers[i].complete();
    await pumpEventQueue();
  }

  Future<void> failSave(int i, Object error) async {
    _completers[i].completeError(error);
    await pumpEventQueue();
  }
}
