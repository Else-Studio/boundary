import 'dart:async';

import 'package:flutter/material.dart';

enum NoticeLevel { info, success, warning, error }

class Notice {
  const Notice(this.message, {this.level = NoticeLevel.error});

  final String message;
  final NoticeLevel level;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Notice && message == other.message && level == other.level;

  @override
  int get hashCode => Object.hash(message, level);
}

class NoticeService {
  final StreamController<Notice> _controller =
      StreamController<Notice>.broadcast(sync: true);

  /// Broadcast; a listener gets only notices shown after it subscribed.
  Stream<Notice> get notices => _controller.stream;

  void show(Notice notice) => _controller.add(notice);

  void dispose() => _controller.close();
}

/// Shows each notice as SnackBar(content: Text(notice.message)) through the
/// nearest ScaffoldMessenger. Cancels its subscription on dispose.
class NoticeSnackBarListener extends StatefulWidget {
  const NoticeSnackBarListener({
    super.key,
    required this.notices,
    required this.child,
  });

  final Stream<Notice> notices;
  final Widget child;

  @override
  State<NoticeSnackBarListener> createState() => _NoticeSnackBarListenerState();
}

class _NoticeSnackBarListenerState extends State<NoticeSnackBarListener> {
  StreamSubscription<Notice>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(NoticeSnackBarListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notices != widget.notices) {
      _subscription?.cancel();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _subscription = widget.notices.listen((notice) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text(notice.message)),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
