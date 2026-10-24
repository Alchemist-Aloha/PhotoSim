import 'dart:async';

import 'package:flutter/material.dart';

/// Keeps workspace feedback out of the canvas, inspector and timeline.
extension WorkspaceFeedback on ScaffoldMessengerState {
  void showWorkspaceFeedback(SnackBar message) {
    final contentKey = GlobalKey<_FeedbackContentState>();
    final controller = showMaterialBanner(
      MaterialBanner(
        elevation: 0,
        content: _FeedbackContent(
          key: contentKey,
          message: message,
          onTimeout: hideCurrentMaterialBanner,
        ),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.action case final action?)
                TextButton(
                  onPressed: () {
                    removeWorkspaceFeedback();
                    action.onPressed();
                  },
                  child: Text(action.label),
                ),
              CloseButton(onPressed: removeWorkspaceFeedback),
            ],
          ),
        ],
        onVisible: () {
          contentKey.currentState?.start();
          message.onVisible?.call();
        },
      ),
    );
    unawaited(controller.closed.then((_) => contentKey.currentState?.cancel()));
  }

  void removeWorkspaceFeedback() => removeCurrentMaterialBanner();
}

class _FeedbackContent extends StatefulWidget {
  const _FeedbackContent({
    super.key,
    required this.message,
    required this.onTimeout,
  });
  final SnackBar message;
  final VoidCallback onTimeout;

  @override
  State<_FeedbackContent> createState() => _FeedbackContentState();
}

class _FeedbackContentState extends State<_FeedbackContent> {
  Timer? timer;

  void start() {
    // Preserve native SnackBar persistence, including action messages that need acknowledgement.
    if (!widget.message.persist) {
      timer = Timer(widget.message.duration, widget.onTimeout);
    }
  }

  void cancel() => timer?.cancel();

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height / 3,
    ),
    child: SingleChildScrollView(primary: false, child: widget.message.content),
  );
}
