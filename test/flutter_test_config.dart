import 'dart:async';

import 'package:boundary/boundary.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  boundaryLogLevel = LogLevel.warning;
  await testMain();
}
