import 'package:flutter/material.dart';

import '../core/local_time.dart';
import '../models/simulation_state.dart';

class TimeSlider extends StatefulWidget {
  const TimeSlider({super.key, required this.state, required this.onChanged});
  final SimulationState state;
  final ValueChanged<SimulationState> onChanged;

  @override
  State<TimeSlider> createState() => _TimeSliderState();
}

class _TimeSliderState extends State<TimeSlider> {
  LocalDay? dragDay;

  @override
  void didUpdateWidget(covariant TimeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.location != widget.state.location) dragDay = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final clock = localClock(
      timestamp: state.timestamp,
      latitude: state.latitude,
      longitude: state.longitude,
    );
    final candidate = clock.time == null ? null : LocalDay(clock.time!);
    final day = dragDay ?? candidate;
    final enabled = day != null && day.supported;
    final message =
        clock.warning ??
        (enabled
            ? 'Local day ${day.date} · ${clock.zoneId}. Daylight-saving gaps are skipped; repeated hours include their timezone abbreviation.'
            : 'Local-day slider unavailable at timezone-rule boundary; use UTC controls.');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text('00:00')),
            Flexible(child: Text('24:00 local', textAlign: TextAlign.end)),
          ],
        ),
        Tooltip(
          message: message,
          child: Slider(
            key: const ValueKey('local-day-slider'),
            min: 0,
            max: enabled ? day.minutes : 1440,
            value: enabled ? day.position(state.timestamp) : 0,
            label: enabled ? day.label(day.position(state.timestamp)) : message,
            semanticFormatterCallback: enabled ? day.label : (_) => message,
            // Keep the date fixed during a drag: 24:00 must not advance a day on every pointer update.
            onChangeStart: enabled
                ? (_) => setState(() => dragDay = day)
                : null,
            onChangeEnd: enabled ? (_) => setState(() => dragDay = null) : null,
            onChanged: enabled
                ? (value) => widget.onChanged(
                    widget.state.copyWith(timestamp: day.utcAt(value)),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
