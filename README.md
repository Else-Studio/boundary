# boundary

Boundary is a Flutter framework for apps whose screens are driven by controllers. It gives you:

- **Controllers** that take actions in and put state out on streams, and release what they own when their screen goes away.
- **Routing driven by a coordinator.** Routes are typed objects. One binding per route says how to build its controller and page, who may see it, and which layout frames it. Guards, modals, back-to-parent and leave guards are built in.
- **Pluggable auth.** A stored-token service covers apps that sign in with their own login call. The HTTP layer adds the token, and a 401 signs the user out.
- **An API client base** that maps HTTP failures to typed exceptions and reads problem+json error bodies.
- **Error handling** that turns errors into notices or pages when a controller asks for it.
- **Auto-saving forms** on reactive_forms, with debounced saves, server patches, server validation errors and a guard against leaving with unsaved changes.
- **Test doubles** for auth, navigation and HTTP, and a harness for controller tests.

## Principles

- **Views only draw and dispatch.** A view draws its controller's streams and sends every user intent as an action. Logic lives in controllers, where it can be tested without widgets.
- **Every side effect starts from an action.** All work begins in `handleAction`, so there is one entry point to read, log and test.
- **Loaded data is an `AsyncResult`:** `Loading`, `Data`, `Failure` or `Empty`. Views show it with `AsyncResultBuilder`.
- **One binding per destination.** The coordinator combines the requested route with the auth state, creates the controller, and disposes it when the route goes away.

## Entry libraries

| Import | What it holds |
|---|---|
| `package:boundary/boundary.dart` | Controllers, routing, the coordinator, auth, HTTP and API clients, errors and notices, `AsyncResult`, logging. |
| `package:boundary/forms.dart` | `FormSession`, `SaveStatus` and `FormLeaveGuard`. |
| `package:boundary/testing.dart` | Test doubles and `ControllerHarness`, for tests only. |
| `package:boundary/formatters.dart` | `AppFormatters` for dates, numbers and currency. Not exported from `boundary.dart`. |
| `package:boundary/oauth.dart` | A deprecated, web-only OAuth2 PKCE service, kept for reference. |

`responsive_framework.dart`, exported from `boundary.dart`, is kept as it is from an earlier version. It is not covered by these docs.

## Documentation

- [GETTING_STARTED.md](GETTING_STARTED.md) builds a small app step by step.
- [doc/building_with_boundary.md](doc/building_with_boundary.md) is the rule book for every feature, and the page to point your app's agents at.
- [doc/](doc/) holds a guide per topic: [architecture](doc/architecture.md), [controllers](doc/controllers.md), [routing](doc/routing.md), [child controllers](doc/sub_controllers.md), [forms](doc/forms.md), [errors](doc/errors.md), [auth](doc/auth.md), [API clients](doc/api_client.md) and [testing](doc/testing.md).
- [CHANGELOG.md](CHANGELOG.md) lists what changed in each version.
- [AGENTS.md](AGENTS.md) is for anyone changing boundary itself.
