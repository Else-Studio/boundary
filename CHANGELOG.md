## 0.5.0 (unreleased)

*   `Error<T>` is now `Failure<T>`, so `dart:core` `Error` is no longer shadowed.
*   `boundaryLogLevel` and `export LogLevel` added: tests and apps set the lowest level `useLogger` prints; quiet loggers still drop verbose and debug.
*   `router.dart` uses `onDidRemovePage` in place of the deprecated `onPopPage`; system back on a modal still calls `dismissModal()`.
*   `HttpService(AuthService, http.BaseClient)`: no `LocaleService`, and no `Accept-Language` header.
*   `BaseAuthService({required loggerLabel})`: no `LocaleService`, and no `ui_locales` query parameter.
*   `AppCoordinator.localeService` and the `LocaleService` registration are removed; `locale_service.dart` is no longer exported from `boundary.dart`.
*   `AppConfig` keeps only `baseUrl` and `debounceTime`; `publicWebOrigin`, `sseWatchdogTimeout` and `sseMinRetryDelay` are removed.
*   `AppFormatters.formatCurrency` requires `symbol`; the `'€ '` default is removed.

## 0.4.1

### Improvements & Bug Fixes
*   **Service Module**: Improved service management based on meeting feedback (cities support, enhanced filtering, etc).
*   **Task Module**: Fixed a critical blockage in the task creation process.

## 0.4.0

### Sales & Customer Module Expansion
*   **Customer Module Completion**: Finalized `CustomerDetail` feature for creating and editing customers and contacts.
*   **Pipeline Visualization**: 
    *   Implemented Kanban Pipelines for Leads and Product Requests.
    *   Integrated creation modals for Leads and Product Requests.
*   **Lead & Product Request Workbenches**:
    *   Developed immersive workspaces for managing Leads and Product Requests.
    *   Extracted `WorkbenchLayout` and `ScopedTaskBoardController` for high code reuse.
*   **Navigation**:
    *   Implemented a toggle to hide WIP features (Projects, Enquiry, Product Request, Customer) in the shell.

## 0.0.1

* Initial release.
