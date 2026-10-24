/// Lets queued microtasks and zero-delay timers run: [times] rounds of
/// `await Future<void>.delayed(Duration.zero)`.
Future<void> pumpEventQueue({int times = 20}) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
