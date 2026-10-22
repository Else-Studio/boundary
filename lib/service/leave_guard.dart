/// A page can register one of these on [NavigationService] to veto or confirm
/// leaving.
abstract interface class LeaveGuard {
  /// Drives the web unload warning.
  bool get hasUnsavedChanges;

  /// `true`: leaving may go ahead.
  Future<bool> mayLeave();
}
