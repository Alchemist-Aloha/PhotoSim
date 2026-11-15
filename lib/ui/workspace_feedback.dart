import 'dart:async';

import 'package:flutter/material.dart';

/// Keeps workspace feedback out of the canvas, inspector and timeline.
extension WorkspaceFeedback on ScaffoldMessengerState {
  void showWorkspaceFeedback(SnackBar message) {
    // The messenger renders a banner in every registered Scaffold (e.g. under
    // the Settings route), so its content must not carry a GlobalKey; the
    // auto-hide timer is shared by every copy instead.
    final expiry = _Expiry();
    final controller = showMaterialBanner(
      MaterialBanner(
        elevation: 0,
        content: _FeedbackContent(message: message, expiry: expiry),
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
          // Preserve native SnackBar persistence, including action messages that need acknowledgement.
          if (!message.persist) {
            expiry.timer ??= Timer(message.duration, hideCurrentMaterialBanner);
          }
          message.onVisible?.call();
        },
      ),
    );
    unawaited(controller.closed.then((_) => expiry.timer?.cancel()));
  }

  void removeWorkspaceFeedback() => removeCurrentMaterialBanner();
}

class _Expiry {
  Timer? timer;
  int copies = 0;
}

class _FeedbackContent extends StatefulWidget {
  const _FeedbackContent({required this.message, required this.expiry});
  final SnackBar message;
  final _Expiry expiry;

  @override
  State<_FeedbackContent> createState() => _FeedbackContentState();
}

class _FeedbackContentState extends State<_FeedbackContent> {
  @override
  void initState() {
    super.initState();
    widget.expiry.copies++;
  }

  @override
  void dispose() {
    // Tearing down the tree does not close the banner; stop its timer here.
    if (--widget.expiry.copies == 0) widget.expiry.timer?.cancel();
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
