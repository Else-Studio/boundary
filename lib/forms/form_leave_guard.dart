import '../service/leave_guard.dart';
import 'form_session.dart';

/// Connects a [FormSession] to leave-guard checks: flush first, then ask
/// [confirm] when that fails or the form is invalid.
class FormLeaveGuard implements LeaveGuard {
  FormLeaveGuard(
    this.session, {
    required this.confirm,
  });

  /// The session to flush before leaving.
  final FormSession session;
  /// Asks the user whether to leave anyway; true leaves.
  final Future<bool> Function() confirm;

  @override
  bool get hasUnsavedChanges => session.hasUnsavedChanges;

  /// No unsaved changes: true. Else [FormSession.flush]: true → true;
  /// false → [confirm].
  @override
  Future<bool> mayLeave() async {
    if (!session.hasUnsavedChanges) return true;
    final flushed = await session.flush();
    if (flushed) return true;
    return confirm();
  }
}
