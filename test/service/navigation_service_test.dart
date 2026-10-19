import 'package:boundary/boundary.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestRoute extends ConfigurationBase {
  final String path;

  const _TestRoute(this.path);

  @override
  Uri get uri => Uri.parse(path);
}

class _TestCallbackRoute extends _TestRoute {
  const _TestCallbackRoute() : super('/callback');
}

class _TestDelegate implements NavigationServiceDelegate {
  final ConfigurationBase loginRoute;

  const _TestDelegate(this.loginRoute);

  @override
  ConfigurationBase? parseUri(Uri uri) => null;

  @override
  ConfigurationBase getLoginRoute() => loginRoute;

  @override
  bool isAuthCallbackRoute(ConfigurationBase config) =>
      config is _TestCallbackRoute;

  @override
  ConfigurationBase getPostLoginDefaultRoute() => const _TestRoute('/home');
}

void main() {
  test('navigateBackOrLogin uses history and falls back to login', () {
    const login = _TestRoute('/login');
    const base = _TestRoute('/base');

    final service = NavigationService(delegate: const _TestDelegate(login));
    service.navigateTo(base);
    service.navigateBackOrLogin();
    expect(service.currentRequestedConfiguration, same(base));
    service.dispose();

    final fallbackService = NavigationService(
      delegate: const _TestDelegate(login),
    );
    fallbackService.navigateBackOrLogin();
    expect(fallbackService.currentRequestedConfiguration, same(login));
    fallbackService.dispose();
  });
  test('does not retain auth callback as navigation history', () {
    const login = _TestRoute('/login');
    const base = _TestRoute('/base');
    const callback = _TestCallbackRoute();

    final service = NavigationService(delegate: const _TestDelegate(login));
    service.navigateTo(base);
    service.navigateTo(callback);
    service.navigateBackOrLogin();

    expect(service.currentRequestedConfiguration, same(base));
    service.dispose();

    final callbackOnlyService = NavigationService(
      delegate: const _TestDelegate(login),
    );
    callbackOnlyService.syncBaseConfiguration(callback);
    callbackOnlyService.navigateBackOrLogin();
    expect(callbackOnlyService.currentRequestedConfiguration, same(login));
    callbackOnlyService.dispose();
  });
}
