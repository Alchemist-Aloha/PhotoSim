import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

const navigationMetersPerSecond = 100.0;

/// Focus-scoped, frame-rate-independent movement; no app-global key interception.
class WasdNavigation extends StatefulWidget {
  const WasdNavigation({
    super.key,
    required this.enabled,
    required this.onMove,
    required this.child,
  });
  final bool enabled;
  final void Function(double forwardMeters, double rightMeters) onMove;
  final Widget child;
  @override
  State<WasdNavigation> createState() => _WasdNavigationState();
}

class _WasdNavigationState extends State<WasdNavigation>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final focus = FocusNode(debugLabel: '3D WASD navigation');
  final pressed = <LogicalKeyboardKey>{};
  late final Ticker ticker = createTicker(tick);
  Duration last = Duration.zero;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    pressed.clear();
    ticker.stop();
    last = Duration.zero;
  }

  @override
  void didUpdateWidget(covariant WasdNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop();
  }

  void tick(Duration elapsed) {
    final seconds =
        ((elapsed - last).inMicroseconds / Duration.microsecondsPerSecond)
            .clamp(0.0, 0.1);
    last = elapsed;
    final forward =
        (pressed.contains(LogicalKeyboardKey.keyW) ? 1 : 0) -
        (pressed.contains(LogicalKeyboardKey.keyS) ? 1 : 0);
    final right =
        (pressed.contains(LogicalKeyboardKey.keyD) ? 1 : 0) -
        (pressed.contains(LogicalKeyboardKey.keyA) ? 1 : 0);
    final length = math.sqrt(forward * forward + right * right);
    if (length > 0 && seconds > 0 && widget.enabled) {
      final distance = seconds * navigationMetersPerSecond / length;
      widget.onMove(forward * distance, right * distance);
    }
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (!const [
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyS,
      LogicalKeyboardKey.keyD,
    ].contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      pressed.remove(event.logicalKey);
      if (pressed.isEmpty) stop();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!widget.enabled ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      stop();
      return KeyEventResult.ignored;
    }
    pressed.add(event.logicalKey);
    if (!ticker.isActive) {
      last = Duration.zero;
      ticker.start();
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    autofocus: true,
    onKeyEvent: key,
    onFocusChange: (focused) {
      if (!focused) stop();
    },
    child: Listener(
      onPointerDown: (_) => focus.requestFocus(),
      child: widget.child,
    ),
  );
}
