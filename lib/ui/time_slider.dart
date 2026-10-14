import 'package:flutter/material.dart';

import '../models/simulation_state.dart';

class TimeSlider extends StatelessWidget {
  const TimeSlider({super.key, required this.state, required this.onChanged});
  final SimulationState state;
  final ValueChanged<SimulationState> onChanged;

  String clock(double value) {
    final minutes = value.round();
    return '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')} UTC';
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Text('00:00'),
      Expanded(
        child: Slider(
          key: const ValueKey('utc-day-slider'),
          min: 0,
          max: 1439,
          value: (state.timestamp.hour * 60 + state.timestamp.minute)
              .toDouble(),
          label: clock(
            (state.timestamp.hour * 60 + state.timestamp.minute).toDouble(),
          ),
          semanticFormatterCallback: clock,
          onChanged: (value) => onChanged(
            state.copyWith(
              timestamp: DateTime.utc(
                state.timestamp.year,
                state.timestamp.month,
                state.timestamp.day,
              ).add(Duration(minutes: value.round())),
            ),
          ),
        ),
      ),
      const Text('23:59 UTC'),
    ],
  );
}
