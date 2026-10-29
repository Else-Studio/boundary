# Working on boundary

This file is for changing boundary itself. To build an app on boundary, read [doc/building_with_boundary.md](doc/building_with_boundary.md) instead.

## Toolchain

- Flutter 3.47.8 (Dart 3.13.7) is pinned in the repository's root `mise.toml`. Run `flutter` and `dart` from inside `boundary/`, so mise picks that version.
- `flutter analyze` must print `No issues found!`. Infos count: the command exits non-zero on them. Do not add `// ignore:` or `// ignore_for_file:` in `lib/`.
- `flutter test --reporter failures-only` runs the suite. The last line is `+N: All tests passed!`, with `~N` for skipped tests. `No tests match` or `No tests ran.` is never a pass.
- Run one file with `flutter test --reporter failures-only test/<path>_test.dart`, and narrow it with `--plain-name "<part of a test name>"`.
- `dart run build_runner build --delete-conflicting-outputs` regenerates generated code. Run it after changing `test/helpers/mocks.dart` or any `@MappableClass`. If it fails with `Invalid kernel binary format`, delete `.dart_tool/build` and run it again.
- `lib/**/*.mapper.dart` and `test/helpers/mocks.mocks.dart` are generated. Never edit them by hand.

## The public API

The public API is what the entry libraries export:

| Library | Holds | Rule |
|---|---|---|
| `lib/boundary.dart` | The core | |
| `lib/forms.dart` | `FormSession`, `FormLeaveGuard` | Not exported from `boundary.dart` |
| `lib/testing.dart` | Test doubles | Not exported from `boundary.dart`. Must not depend on `flutter_test`. |
| `lib/formatters.dart` | `AppFormatters` | Not exported from `boundary.dart` |
| `lib/oauth.dart` | The deprecated web OAuth service | Not exported from `boundary.dart` |

When you add a public type, export it from the right library. When you remove one, remove its export. `lib/service/locale_service.dart` is deliberately not exported or used; leave it as it is. `lib/responsive_framework.dart` is kept unchanged from 0.4.

Write a doc comment on every public member you add or change. Say what it does and what it returns or throws, in plain sentences. Agents reading an app's dependencies see these comments first.

## How the framework is meant to behave

The guides in `doc/` describe the intended behaviour, and the tests lock it in. Read the guide for the area before you change it:

| Area | Guide | Main files |
|---|---|---|
| Controllers, `own`, `emit`, `enter`, `update` | [doc/controllers.md](doc/controllers.md) | `controller.dart` |
| Child controllers and slots | [doc/sub_controllers.md](doc/sub_controllers.md) | `controller.dart`, `controller_slot.dart`, `controller_factory.dart` |
| Route resolution, access, guards, layouts | [doc/architecture.md](doc/architecture.md), [doc/routing.md](doc/routing.md) | `app_coordinator.dart`, `route_table.dart`, `router.dart` |
| Navigation, back, leave guards | [doc/routing.md](doc/routing.md) | `service/navigation_service.dart` |
| Auth and the 401 rule | [doc/auth.md](doc/auth.md) | `service/auth_service.dart`, `service/stored_token_auth_service.dart`, `service/http_service.dart` |
| API clients and exceptions | [doc/api_client.md](doc/api_client.md) | `service/base_api_client.dart` |
| Error policy and notices | [doc/errors.md](doc/errors.md) | `error_policy.dart`, `notice.dart` |
| Forms | [doc/forms.md](doc/forms.md) | `forms/form_session.dart`, `forms/form_leave_guard.dart` |
| Where a page's controller is provided, `AsyncResultBuilder` | [doc/views.md](doc/views.md) | `route_table.dart`, `async_result_builder.dart` |

A few behaviours are easy to break by accident:

- The coordinator resolves one change at a time, in order. Keep the queue in `_queueReconcile`.
- While the auth state is unknown, the requested route is shown and no guard runs.
- A replaced controller is disposed after the next frame, not at once.
- An action's error goes to that controller's `onError` only. It is never forwarded to a parent.
- Every 401 on a call that needed a token goes to `refreshAfterUnauthorized`, the second one too, so a provider that cannot refresh signs out before the error reaches the app.
- `FormSession` saves only user edits: value changes on dirty controls. `patchFromServer` never saves.
- User-facing texts are English sentences, not locale keys.

## Tests

- `test/` mirrors `lib/`. Tests import boundary through `package:boundary/...` paths and test only public members.
- Use the three helpers in `test/helpers/`:
  - `MockDependencyProvider` holds happy-path mocks;
  - `SutFactory` is the only place a class under test is built (except the `AppCoordinator` wiring inside it);
  - `ModelFactory` builds test data.
- Mocks come from `@GenerateMocks` in `test/helpers/mocks.dart`.
- Declare fake routes and fake controllers at the top of the test file that uses them, as `test/core/app_coordinator_lifecycle_test.dart` does.
- Allowed: unit tests, and widget tests of boundary's own widgets and router. No golden tests, no `integration_test`, no real HTTP server, no real platform plugins.
- Wait for async work with `pumpEventQueue()`, never with `Future.delayed(Duration.zero)` or a guessed duration. Edit forms through `FormFixture.edit`, which marks the control dirty first.
- `test/flutter_test_config.dart` sets `boundaryLogLevel` to `warning`. A test that changes a top-level setting restores it in `tearDown`.
- Name tests by behaviour, in the existing "should …" or plain-sentence style.

## Before you finish a change

- `flutter analyze` is clean and the whole suite passes.
- Every public API change has one line in `CHANGELOG.md`, under the top version's heading.
- The guides in `doc/`, `GETTING_STARTED.md` and the doc comments still describe the code. Search the docs for each name you changed. Where a guide and the code disagree, fix one of them.
- Code in `GETTING_STARTED.md` must still compile against the change.
- No new dependency in `pubspec.yaml` unless the change was agreed to need one.
- Nothing names the app boundary came from. `grep -rn "vh_web\|VH\|Keycloak\|keycloak\|Else Studio" . --include=*.md --include=*.dart --exclude=AGENTS.md` finds only the history line in `CHANGELOG.md`.

## In the playrecord repository

Boundary is developed inside playrecord. There, planned work runs as slices. The decisions behind boundary are in `plans/boundary/rules.md`, and the slice workflow settings are in `slice-workflow.md` at the repository root.
