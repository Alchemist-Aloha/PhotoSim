import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../data/saved_plans.dart';
import '../data/raster_cache.dart';

import '../core/local_time.dart';

import '../models/simulation_state.dart';
import '../ui/camera_inspector.dart';
import '../ui/map_workspace.dart';
import '../ui/simulation_workspace.dart';
import '../ui/time_slider.dart';

class PhotoSimApp extends StatelessWidget {
  const PhotoSimApp({super.key, this.plans, this.rasterCache});
  final PlanRepository? plans;
  final RasterCache? rasterCache;

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
    home: WorkspaceShell(plans: plans, rasterCache: rasterCache),
  );
}

enum Workspace { map, simulation }

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({super.key, this.plans, this.rasterCache});
  final PlanRepository? plans;
  final RasterCache? rasterCache;

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell>
    with WidgetsBindingObserver {
  // Keep service cooldowns/connections alive across Map/3D workspace recreation.
  final terrainClient = http.Client();
  SimulationState state = SimulationState();
  Workspace workspace = Workspace.map;
  bool inspectorVisible = true;
  bool cleanPreview = false;
  RasterCache? rasterCache;
  String? cacheError;

  Future<void> initializeCache() async {
    try {
      final cache =
          widget.rasterCache ??
          RasterCache(
            Directory(
              '${(await getApplicationCacheDirectory()).path}/photosim',
            ),
            settingsFile: File(
              '${(await getApplicationSupportDirectory()).path}/photosim/cache-settings.json',
            ),
          );
      await cache.initialize();
      if (mounted) setState(() => rasterCache = cache);
    } on Exception {
      if (mounted) {
        setState(
          () => cacheError = 'Disk cache settings unavailable. Restart after checking disk permissions.',
        );
      }
    }
  }

  Future<void> setCleanPreview(bool value) async {
    setState(() {
      if (value) stopPlayback();
      cleanPreview = value;
    });
    try {
      await const MethodChannel('photosim/window')
          .invokeMethod<void>('fullscreen', value);
    } on MissingPluginException {
      // Unit-test/embedded hosts can still show the clean content viewport.
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Window fullscreen unavailable: ${error.message}'),
          ),
        );
      }
    }
  }

  Timer? playback;
  int playbackSpeed = 5;
  DateTime get nextPlaybackTime =>
      state.timestamp.add(Duration(seconds: playbackSpeed * 12));
  PlanRepository? _plans;
  bool planBusy = false;
  int openedPlan = 0;

  Future<void> managePlans(bool save) async {
    if (planBusy) return;
    setState(() {
      stopPlayback();
      planBusy = true;
    });
    try {
      final store = _plans ??=
          widget.plans ??
          PlanRepository(
            Directory(
              '${(await getApplicationSupportDirectory()).path}/photosim/plans-v1',
            ),
          );
      if (!mounted) return;
      if (save) {
        var planName = 'Photography plan';
        final name = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Save photography plan'),
            content: TextFormField(
              initialValue: planName,
              onChanged: (value) => planName = value,
              autofocus: true,
              maxLength: 80,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a plan name'
                  : null,
              decoration: const InputDecoration(labelText: 'Plan name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (planName.trim().isNotEmpty) {
                    Navigator.pop(context, planName.trim());
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (!mounted || name == null) return;
        final file = await store.save(SavedPlan(name, state));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved $name · ${file.path}')));
      } else {
        final loaded = await store.loadAll();
        if (!mounted) return;
        final selected = await showDialog<SavedPlan>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Open photography plan'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loaded.unreadable > 0)
                    Text(
                      '${loaded.unreadable} unreadable plans left unchanged.',
                    ),
                  if (loaded.plans.isEmpty) const Text('No saved plans found.'),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: loaded.plans.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(loaded.plans[i].name),
                        subtitle: Text(
                          '${loaded.plans[i].state.timestamp.toIso8601String()} · ${loaded.plans[i].state.target.label}',
                        ),
                        onTap: () => Navigator.pop(context, loaded.plans[i]),
                      ),
                    ),
                  ),
                  SelectableText('Storage: ${store.directory.path}'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
        if (selected != null && mounted) {
          setState(() {
            state = selected.state;
            workspace = Workspace.map;
            openedPlan++;
          });
        }
      }
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plan ${save ? 'save' : 'load'} failed: $failure'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => planBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(initializeCache());
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
        final next = nextPlaybackTime;
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
    terrainClient.close();
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
    final target = state.targetPosition;
    final clock = localClock(
      timestamp: state.timestamp,
      latitude: state.latitude,
      longitude: state.longitude,
    );
    final local = clock.time;
    final inspector = CameraInspector(
      state: state,
      onChanged: update,
      rasterCache: rasterCache,
      cacheError: cacheError,
    );
    final scaffold = Scaffold(
      drawer: cleanPreview
          ? null
          : NavigationDrawer(
              selectedIndex: workspace.index,
              onDestinationSelected: (index) {
                setState(() => workspace = Workspace.values[index]);
                Navigator.of(context).pop();
              },
              children: const [
                Padding(
                  padding: EdgeInsets.fromLTRB(28, 24, 16, 16),
                  child: Text('PhotoSim'),
                ),
                NavigationDrawerDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: Text('Map'),
                ),
                NavigationDrawerDestination(
                  icon: Icon(Icons.landscape_outlined),
                  selectedIcon: Icon(Icons.landscape),
                  label: Text('3D Preview'),
                ),
              ],
            ),
      floatingActionButton: cleanPreview
          ? FloatingActionButton.small(
              tooltip: 'Exit fullscreen preview (Esc)',
              onPressed: () => setCleanPreview(false),
              child: const Icon(Icons.fullscreen_exit),
            )
          : null,
      appBar: cleanPreview
          ? null
          : AppBar(
              title: const Text('PhotoSim'),
              leading: Builder(
                builder: (context) => IconButton(
                  tooltip: 'Open navigation',
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              actions: [
                PopupMenuButton<bool>(
                  tooltip: 'Photography plans',
                  enabled: !planBusy,
                  icon: const Icon(Icons.folder_outlined),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: true, child: Text('Save plan')),
                    PopupMenuItem(value: false, child: Text('Open plan')),
                  ],
                  onSelected: managePlans,
                ),
                PopupMenuButton<CelestialTarget>(
                  tooltip: 'Select astronomical target',
                  icon: const Icon(Icons.track_changes),
                  initialValue: state.target,
                  itemBuilder: (_) => [
                    for (final target in CelestialTarget.values)
                      PopupMenuItem(value: target, child: Text(target.label)),
                  ],
                  onSelected: (value) => update(state.copyWith(target: value)),
                ),
                IconButton(
                  tooltip: 'Aim at selected target',
                  icon: const Icon(Icons.gps_fixed),
                  onPressed: target == null
                      ? null
                      : () => update(
                          state.copyWith(
                            azimuth: target.azimuth,
                            pitch: target.altitude,
                          ),
                        ),
                ),
                IconButton(
                  tooltip: 'Fullscreen preview',
                  icon: const Icon(Icons.fullscreen),
                  onPressed: workspace != Workspace.simulation
                      ? null
                      : () => setCleanPreview(true),
                ),
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
              ? MapWorkspace(
                  key: ValueKey(openedPlan),
                  state: state,
                  onChanged: update,
                )
              : rasterCache == null
              ? Center(
                  child: Text(cacheError ?? 'Loading disk cache settings…'),
                )
              : SimulationWorkspace(
                  rasterCache: rasterCache,
                  httpClient: terrainClient,
                  state: state,
                  cleanPreview: cleanPreview,
                  onChanged: update,
                  onPausePlayback: () => setState(stopPlayback),
                );
          return Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: viewport),
                    if (!cleanPreview &&
                        inspectorVisible &&
                        constraints.maxWidth >= 900) ...[
                      const VerticalDivider(width: 1),
                      SizedBox(width: 310, child: inspector),
                    ],
                  ],
                ),
              ),
              if (!cleanPreview &&
                  inspectorVisible &&
                  constraints.maxWidth < 900)
                SizedBox(height: 240, child: inspector),
              if (!cleanPreview) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Tooltip(
                    message:
                        'Estimated timezone from bundled coordinate mapping. Verify near borders and offshore. '
                        'Local rules are supported for 1970–2037. The slider uses the local day; date/time picker and astronomy remain UTC.',
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
                      if (target != null)
                        Tooltip(
                          message: 'Center inside the rectangular lens frustum; terrain visibility unknown. Target does not lock camera orientation.',
                          child: Text(
                            '${state.target.label}: ${state.containsDirection(target.direction) ? 'inside' : 'outside'} FOV · alt ${target.altitude.toStringAsFixed(1)}° · offset ${state.targetAngularOffset!.toStringAsFixed(1)}°',
                          ),
                        ),
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
                            ? 'Play time ($playbackSpeed simulated minutes per second)'
                            : 'Pause time',
                        icon: Icon(
                          playback == null ? Icons.play_arrow : Icons.pause,
                        ),
                        onPressed:
                            playback == null && nextPlaybackTime.year > 2100
                            ? null
                            : togglePlayback,
                      ),
                      PopupMenuButton<int>(
                        tooltip: 'Playback speed',
                        icon: const Icon(Icons.speed),
                        initialValue: playbackSpeed,
                        itemBuilder: (_) => [
                          for (final speed in [1, 5, 30, 60])
                            PopupMenuItem(
                              value: speed,
                              child: Text('$speed min/s'),
                            ),
                        ],
                        onSelected: (value) =>
                            setState(() => playbackSpeed = value),
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
            ],
          );
        },
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (cleanPreview) unawaited(setCleanPreview(false));
        },
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }
}
