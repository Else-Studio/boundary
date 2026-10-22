import 'package:auto_injector/auto_injector.dart';

import 'controller.dart';

/// One factory per child type, injected like a service.
class ControllerFactory<C extends Controller> {
  const ControllerFactory(this._create);

  final C Function() _create;

  /// A new controller on every call.
  C create() => _create();
}

/// Registers a `ControllerFactory<C>` in [injector]; each
/// [ControllerFactory.create] calls [create] with that injector. Call it in
/// registerDependencies, before commit.
void addControllerFactory<C extends Controller>(
  AutoInjector injector,
  C Function(AutoInjector injector) create,
) {
  injector.addInstance<ControllerFactory<C>>(
    ControllerFactory<C>(() => create(injector)),
  );
}
