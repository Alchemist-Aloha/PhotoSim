import 'dart:async';

import 'package:flutter/material.dart';

import '../core/local_time.dart';

import '../models/simulation_state.dart';
import '../ui/camera_inspector.dart';
import '../ui/map_workspace.dart';
import '../ui/simulation_workspace.dart';
import '../ui/time_slider.dart';

class PhotoSimApp extends StatelessWidget {
  const PhotoSimApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PhotoSim',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF34D9B0),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: const WorkspaceShell(),
  );
}

enum Workspace { map, simulation }

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({super.key});

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell>
    with WidgetsBindingObserver {
  SimulationState state = SimulationState();
  Workspace workspace = Workspace.map;
  bool inspectorVisible = true;

  Timer? playback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void stopPlayback() {
    playback?.cancel();
    playback = null;
  }

  void togglePlayback() => setState(() {
    if (playback != null) {
      stopPlayback();
    } else {
      playback = Timer.periodic(const Duration(milliseconds: 200), (_) {
        final next = state.timestamp.add(const Duration(minutes: 1));
        if (next.year > 2100) {
          setState(stopPlayback);
        } else {
          setState(() => state = state.copyWith(timestamp: next));
        }
      });
    }
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed && playback != null) {
      setState(stopPlayback);
    }
  }

  @override
  void dispose() {
    stopPlayback();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void update(SimulationState next) => setState(() {
    if (next.timestamp != state.timestamp) stopPlayback();
    state = next;
  });

  Future<void> chooseTime() async {
    setState(stopPlayback);
    final date = await showDatePicker(
      context: context,
      helpText: 'Choose simulation date (UTC)',
      initialDate: state.timestamp,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      helpText: 'Choose simulation time (UTC)',
      initialTime: TimeOfDay.fromDateTime(state.timestamp),
    );
    if (time == null || !mounted) return;
    update(
      state.copyWith(
        timestamp: DateTime.utc(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      ),
    );
  }

  Widget timeStep(int hours) {
    final next = state.timestamp.add(Duration(hours: hours));
    return IconButton(
      tooltip: hours < 0 ? 'Earlier by one hour' : 'Later by one hour',
      icon: Icon(hours < 0 ? Icons.chevron_left : Icons.chevron_right),
      onPressed: next.year < 1900 || next.year > 2100
          ? null
          : () => update(state.copyWith(timestamp: next)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sky = state.sky;
    final clock = localClock(
      timestamp: state.timestamp,
      latitude: state.latitude,
      longitude: state.longitude,
    );
    final local = clock.time;
    final inspector = CameraInspector(state: state, onChanged: update);
    return Scaffold(
      appBar: AppBar(
        title: const Text('PhotoSim'),
        actions: [
          SegmentedButton<Workspace>(
            segments: const [
              ButtonSegment(
                value: Workspace.map,
                label: Text('Map'),
                icon: Icon(Icons.map_outlined),
              ),
              ButtonSegment(
                value: Workspace.simulation,
                label: Text('3D Preview'),
                icon: Icon(Icons.landscape_outlined),
              ),
            ],
            selected: {workspace},
            onSelectionChanged: (value) =>
                setState(() => workspace = value.single),
          ),
          const SizedBox(width: 16),
          IconButton(
            tooltip: 'Toggle camera inspector',
            onPressed: () =>
                setState(() => inspectorVisible = !inspectorVisible),
            icon: const Icon(Icons.tune),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = workspace == Workspace.map
              ? MapWorkspace(state: state, onChanged: update)
              : SimulationWorkspace(state: state, onChanged: update);
          return Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: viewport),
                    if (inspectorVisible && constraints.maxWidth >= 900) ...[
                      const VerticalDivider(width: 1),
                      SizedBox(width: 310, child: inspector),
                    ],
                  ],
                ),
              ),
              if (inspectorVisible && constraints.maxWidth < 900)
                SizedBox(height: 240, child: inspector),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Tooltip(
                  message:
                      'Estimated timezone from bundled coordinate mapping. Verify near borders and offshore. '
                      'Local rules are supported for 1970–2037; all controls and astronomy remain UTC.',
                  child: Text(
                    local == null
                        ? clock.warning!
                        : 'Estimated local: ${local.toIso8601String().substring(0, 16).replaceAll('T', ' ')} '
                              '${local.timeZoneName} (${formatUtcOffset(local.timeZoneOffset)}) · ${clock.zoneId}',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TimeSlider(state: state, onChanged: update),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(Icons.schedule, size: 20),
                    TextButton(
                      onPressed: chooseTime,
                      child: Text(
                        '${state.timestamp.toIso8601String().substring(0, 16).replaceAll('T', ' ')} UTC',
                      ),
                    ),
                    timeStep(-1),
                    timeStep(1),
                    IconButton(
                      tooltip: playback == null
                          ? 'Play time (5 simulated minutes per second)'
                          : 'Pause time',
                      icon: Icon(
                        playback == null ? Icons.play_arrow : Icons.pause,
                      ),
                      onPressed:
                          playback == null &&
                              state.timestamp
                                      .add(const Duration(minutes: 1))
                                      .year >
                                  2100
                          ? null
                          : togglePlayback,
                    ),
                    Text(
                      'Sun az ${sky.sun.azimuth.toStringAsFixed(1)}° · alt ${sky.sun.altitude.toStringAsFixed(1)}°',
                    ),
                    Text(
                      'Moon az ${sky.moon.azimuth.toStringAsFixed(1)}° · alt ${sky.moon.altitude.toStringAsFixed(1)}° · '
                      '${(sky.moonIllumination * 100).toStringAsFixed(0)}% ${sky.moonWaxing ? 'waxing' : 'waning'}',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
