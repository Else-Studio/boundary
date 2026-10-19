import 'package:boundary/app_coordinator_delegate.dart';
import 'package:boundary/controller.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';

import 'package:boundary/service/auth_service.dart';
import 'package:boundary/service/navigation_service.dart';

// This file is used to generate the mock classes for our services.
// After adding or modifying the list of mocks, run the following command
// in your terminal to generate/update the mocks.mocks.dart file:
//
// flutter pub run build_runner build --delete-conflicting-outputs

@GenerateMocks([
  AuthService,
  NavigationService,
  http.BaseClient,
  AppCoordinatorDelegate,
  Controller,
])
void main() {}
