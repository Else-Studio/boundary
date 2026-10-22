import 'unload_warning_stub.dart'
    if (dart.library.js_interop) 'unload_warning_web.dart' as impl;

/// Attaches (web) or no-ops (elsewhere) a browser unload warning driven by
/// [hasUnsavedChanges].
abstract interface class UnloadWarning {
  void attach(bool Function() hasUnsavedChanges);
  void dispose();
}

UnloadWarning createUnloadWarning() => impl.createUnloadWarning();
