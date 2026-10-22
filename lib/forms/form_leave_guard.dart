import '../service/leave_guard.dart';
import 'form_session.dart';

/// Connects a [FormSession] to leave-guard checks: flush first, then ask
/// [confirm] when that fails or the form is invalid.
class FormLeaveGuard implements LeaveGuard {
  FormLeaveGuard(
    this.session, {
    required this.confirm,
  });

  final FormSession session;
  final Future<bool> Function() confirm;

  @override
  bool get hasUnsavedChanges => throw UnimplementedError('not implemented');

  @override
  Future<bool> mayLeave() => throw UnimplementedError('not implemented');
}
