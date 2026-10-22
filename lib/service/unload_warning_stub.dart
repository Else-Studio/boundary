import 'unload_warning.dart';

class _StubUnloadWarning implements UnloadWarning {
  @override
  void attach(bool Function() hasUnsavedChanges) {}

  @override
  void dispose() {}
}

UnloadWarning createUnloadWarning() => _StubUnloadWarning();
