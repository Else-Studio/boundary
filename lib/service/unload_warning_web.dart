import 'unload_warning.dart';

/// Web beforeunload listener. Behaviour is filled in by the implementer.
class _WebUnloadWarning implements UnloadWarning {
  @override
  void attach(bool Function() hasUnsavedChanges) {}

  @override
  void dispose() {}
}

UnloadWarning createUnloadWarning() => _WebUnloadWarning();
