# Errors

This page explains where errors go in a boundary app, and how to show them to the user: inline, as a notice, as a failed load, or as an error page. It also lists the error pages the coordinator shows by itself. The exceptions an API call can throw are listed in [api_client.md](api_client.md).

## Where errors go

| Source | Goes to |
|---|---|
| An action: anything thrown by `handleAction`, sync or async | The controller's `onError(error, stackTrace)` |
| A stream the controller listens to with `listenTo`: an error event, or a throw from the handler | The controller's `onError` |
| A child controller's action | The child's own `onError`. Not the parent's. |
| A `FormSession` save | The session's `onSaveError` |
| A guard that throws, a redirect loop, an auth stream error | An error page, shown by the coordinator |

The default `onError` logs the error with `appLogger.error` and does nothing else. The user sees nothing unless the controller decides how to show it.

## Choosing how to show an error

**Inline,** next to what failed. Catch the exception you expect in `handleAction`, and put a message on a stream:

```dart
try {
  await _auth.signIn(credentials);
} on CredentialsRejectedException catch (e) {
  emit(_error, _errors.messageFor(e));
}
```

`ErrorPolicy.messageFor` gives the same English text a notice would use. Use it so that inline messages and notices agree.

**As a failed load.** When loading a page's data fails, emit a `Failure` so the page can show it, with a retry button:

```dart
} catch (e, s) {
  emit(_list, Failure<List<CaseSummary>>(e, stackTrace: s));
}
```

**As a notice,** a short message in a SnackBar, for failures that are not tied to one spot on the page. Let the error reach `onError`, and pass it to the error policy there:

```dart
@override
void onError(Object error, StackTrace stackTrace) {
  _errors.handle(error, stackTrace);
}
```

Take the `ErrorPolicy` in the controller's constructor: `i.get<ErrorPolicy>()` in the binding. For a form, pass `onSaveError: _errors.handle` to the `FormSession`.

**As a page,** for errors that make the page useless. Map them in your error policy's `pageFor`, shown below, or navigate to an `ErrorRoute` yourself.

## The error policy

`ErrorPolicy.handle(error, stackTrace)` does this:

1. A `SessionTerminatedException` does nothing more than log. The session has already ended, and the auth service is signing the user out, which shows the login page.
2. It logs the error: a warning for an `ApiException`, an error for anything else.
3. If `pageFor(error)` returns a route, it navigates there and stops.
4. Otherwise it shows a notice with `messageFor(error)` at `levelFor(error)`.

The default `messageFor`:

| Error | Message |
|---|---|
| `InvalidInputException` with violation messages | The messages, one per line |
| `InvalidInputException` without them | The exception's message |
| `NetworkException` | "Could not connect. Please check your network connection." |
| `DataParsingException` | "Something went wrong." |
| Any other `ApiException` | The exception's message |
| Anything else | "Something went wrong." |

The default `levelFor` is `warning` for a `RateLimitExceededException` and `error` for everything else. The default `pageFor` returns null, so every error becomes a notice.

### Changing the policy

Subclass `ErrorPolicy` and override what you need. A server's own fields, such as `reason`, are in `problem.extensions`:

```dart
class AppErrorPolicy extends ErrorPolicy {
  AppErrorPolicy(super.notices, super.navigation);

  @override
  ConfigurationBase? pageFor(Object error) {
    if (error is ForbiddenException) {
      return const ErrorRoute(message: 'You cannot open this page.');
    }
    return null;
  }

  @override
  String messageFor(Object error) {
    if (error is ApiException &&
        error.problem?.extensions['reason'] == 'not_allowed') {
      return 'You are not allowed to do that.';
    }
    return super.messageFor(error);
  }
}
```

Give it to the coordinator from your delegate. The coordinator registers it as the app's `ErrorPolicy`:

```dart
@override
ErrorPolicy createErrorPolicy(
  NoticeService notices,
  NavigationService navigation,
) =>
    AppErrorPolicy(notices, navigation);
```

Override `messageFor` too if your app is not in English.

## Notices

A `Notice` is a message and a `NoticeLevel`: `info`, `success`, `warning` or `error`. `NoticeService.show(notice)` puts it on the `notices` stream. The stream is broadcast, so a listener gets only the notices shown after it subscribed.

A controller can show its own notice, for example after an action that has no visible result:

```dart
_notices.show(const Notice('Case closed.', level: NoticeLevel.success));
```

`NoticeSnackBarListener` shows each notice as a `SnackBar` through the nearest `ScaffoldMessenger`. Put it in `MaterialApp.router`'s `builder`, so it sits below the app's `ScaffoldMessenger` and above every page:

```dart
builder: (context, child) => NoticeSnackBarListener(
  notices: coordinator.injector.get<NoticeService>().notices,
  child: child!,
),
```

The listener shows only the message. To style notices by level, write your own listener on the same stream.

## Error pages from the coordinator

The coordinator shows an `ErrorRoute` by itself in these cases:

| Situation | Message |
|---|---|
| The auth state stream reports an error | The session could not be checked. |
| A guard throws | A page check failed. |
| Guards redirect more than five times in a row | Opening that page kept redirecting. |
| No page can be shown, and the auth state is known | The app could not decide which page to show. |

Only the first sets `ErrorRoute.isSessionTermination` to true. The default error page shows "Something went wrong", the message, and a "Back" button. To show your own page, bind `ErrorRoute` yourself, as [routing.md](routing.md), "Error and not-found pages", explains.

## A 401 means the session ended

A 401 on a call that needed a token signs the user out before the error reaches your code. It arrives as a `SessionTerminatedException`, and the error policy ignores it. A 401 on a call that needed no token, such as a refused password at login, is a `CredentialsRejectedException`, which you show like any other error. [auth.md](auth.md) explains the rule.
