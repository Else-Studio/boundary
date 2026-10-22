import 'dart:async';

import 'package:web/web.dart' as web;

import 'unload_warning.dart';

/// Web beforeunload listener driven by [NavigationService.hasUnsavedChanges].
class _WebUnloadWarning implements UnloadWarning {
  StreamSubscription<web.BeforeUnloadEvent>? _sub;

  @override
  void attach(bool Function() hasUnsavedChanges) {
    _sub?.cancel();
    _sub = web.EventStreamProviders.beforeUnloadEvent
        .forTarget(web.window)
        .listen((event) {
      if (!hasUnsavedChanges()) return;
      event.preventDefault();
      event.returnValue = '';
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

UnloadWarning createUnloadWarning() => _WebUnloadWarning();
