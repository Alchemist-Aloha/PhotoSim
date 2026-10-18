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

  late String cleanComposition;
  String? currentPlanName;
  String get composition => SavedPlan('Composition', state).encode();
  bool get hasUnsavedChanges => composition != cleanComposition;

  Future<bool> savePlan(PlanRepository store) async {
    var planName = currentPlanName ?? 'Photography plan';
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
    if (!mounted || name == null) return false;
    final snapshot = SavedPlan(name, state);
    final file = await store.save(snapshot);
    if (!mounted) return false;
    setState(() {
      cleanComposition = SavedPlan('Composition', snapshot.state).encode();
      currentPlanName = name;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hasUnsavedChanges
              ? 'Snapshot saved. Newer changes remain unsaved; save them before opening another plan.'
              : 'Saved $name · ${file.path}',
        ),
      ),
    );
    return !hasUnsavedChanges;
  }

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
        await savePlan(store);
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
          if (hasUnsavedChanges) {
            final decision = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Save changes before opening another plan?'),
                content: Text(
                  'Opening "${selected.name}" will replace your unsaved composition.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'discard'),
                    child: const Text('Discard changes'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, 'save'),
                    child: const Text('Save changes'),
                  ),
                ],
              ),
            );
            if (!mounted || decision == null) return;
            if (decision == 'save' && !await savePlan(store)) return;
            if (!mounted) return;
          }
          setState(() {
            state = selected.state;
            cleanComposition = composition;
            currentPlanName = selected.name;
            workspace = Workspace.map;
            openedPlan++;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Could not save or open the plan. Your current composition is unchanged. Check storage space and folder permissions, then try again.',
            ),
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
    cleanComposition = composition;
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

  String localTimeLabel(DateTime timestamp) {
    final clock = localClock(
      timestamp: timestamp,
      latitude: state.latitude,
      longitude: state.longitude,
    );
    final local = clock.time;
    return local == null
        ? clock.warning!
        : 'Estimated local: ${local.toIso8601String().substring(0, 16).replaceAll('T', ' ')} '
              '${local.timeZoneName} (${formatUtcOffset(local.timeZoneOffset)}) · ${clock.zoneId}';
  }

  Future<void> chooseTime() async {
    setState(stopPlayback);
    final clock = localClock(
      timestamp: state.timestamp,
      latitude: state.latitude,
      longitude: state.longitude,
    );
    var utcFallback = clock.time == null;
    final initial = clock.time ?? state.timestamp;
    var draft = DateTime.utc(
      initial.year,
      initial.month,
      initial.day,
      initial.hour,
      initial.minute,
      initial.second,
      initial.millisecond,
      initial.microsecond,
    );
    DateTime? occurrence = state.timestamp;
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDraft) {
          final candidates = utcFallback
              ? [draft]
              : localTimeCandidates(
                  wallTime: draft,
                  latitude: state.latitude,
                  longitude: state.longitude,
                );
          final resolved = candidates.length == 1
              ? candidates.single
              : candidates.contains(occurrence)
              ? occurrence
              : null;
          final basis = utcFallback ? 'UTC' : 'Local';
          return AlertDialog(
            title: Text(
              utcFallback
                  ? clock.time == null
                        ? 'Edit UTC (local time unavailable)'
                        : 'Edit simulation time (UTC)'
                  : 'Edit local shooting time',
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      utcFallback
                          ? '${clock.warning ?? 'UTC editing selected'}. UTC editing preserves the full 1900–2100 simulation range.'
                          : 'Camera timezone: ${clock.zoneId}. Enter local date and time; UTC is calculated automatically.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            '$basis date: ${draft.toIso8601String().substring(0, 10)}',
                          ),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              helpText: 'Choose simulation date ($basis)',
                              initialDate: draft,
                              firstDate: DateTime(utcFallback ? 1900 : 1969),
                              lastDate: DateTime(
                                utcFallback ? 2100 : 2038,
                                12,
                                31,
                              ),
                            );
                            if (date == null || !context.mounted) return;
                            setDraft(() {
                              draft = DateTime.utc(
                                date.year,
                                date.month,
                                date.day,
                                draft.hour,
                                draft.minute,
                              );
                              occurrence = null;
                            });
                          },
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label: Text(
                            '$basis time: ${draft.toIso8601String().substring(11, 16)}',
                          ),
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              helpText: 'Choose simulation time ($basis)',
                              initialTime: TimeOfDay.fromDateTime(draft),
                            );
                            if (time == null || !context.mounted) return;
                            setDraft(() {
                              draft = DateTime.utc(
                                draft.year,
                                draft.month,
                                draft.day,
                                time.hour,
                                time.minute,
                              );
                              occurrence = null;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (candidates.isEmpty)
                      Semantics(
                        liveRegion: true,
                        child: const Text(
                          'This local time does not exist or falls outside supported timezone rules (1970–2037 UTC). Choose another date or time.',
                        ),
                      ),
                    if (candidates.length > 1) ...[
                      const Text(
                        'This local time occurs twice when clocks move back. Choose which occurrence you mean.',
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<DateTime>(
                        key: ValueKey(draft),
                        initialValue: resolved,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Time occurrence',
                        ),
                        items: [
                          for (final utc in candidates)
                            DropdownMenuItem(
                              value: utc,
                              child: Text(
                                '${localClock(timestamp: utc, latitude: state.latitude, longitude: state.longitude).time!.timeZoneName} · ${utc.toIso8601String().substring(0, 16).replaceAll('T', ' ')} UTC',
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setDraft(() => occurrence = value),
                      ),
                    ],
                    if (resolved != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          'UTC equivalent: ${resolved.toIso8601String().substring(0, 16).replaceAll('T', ' ')} UTC',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    if (utcFallback && resolved != null)
                      Text(localTimeLabel(resolved)),
                    if (!utcFallback)
                      TextButton(
                        onPressed: () => setDraft(() {
                          draft = resolved ?? state.timestamp;
                          utcFallback = true;
                          occurrence = null;
                        }),
                        child: const Text('Use UTC instead (1900–2100)'),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'Local time is estimated from the camera location. Verify near timezone borders. Local rules cover 1970–2037.',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: resolved == null
                    ? null
                    : () => Navigator.pop(context, resolved),
                child: const Text('Apply time'),
              ),
            ],
          );
        },
      ),
    );
    if (selected != null && mounted) {
      update(state.copyWith(timestamp: selected));
    }
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
    final editingTime = clock.time ?? state.timestamp;
    final inspector = CameraInspector(
      state: state,
      onChanged: update,
      rasterCache: rasterCache,
      cacheError: cacheError,
    );
    final scaffold = Scaffold(
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
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PhotoSim'),
                  Text(
                    hasUnsavedChanges
                        ? 'Unsaved changes'
                        : currentPlanName == null
                        ? 'New plan'
                        : 'Saved · $currentPlanName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
      body: Row(
        children: [
          if (!cleanPreview) ...[
            NavigationRail(
              selectedIndex: workspace.index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (index) =>
                  setState(() => workspace = Workspace.values[index]),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: Text('Map'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.landscape_outlined),
                  selectedIcon: Icon(Icons.landscape),
                  label: Text('3D Preview'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = workspace == Workspace.map
                    ? MapWorkspace(
                        key: ValueKey(openedPlan),
                        state: state,
                        onChanged: update,
                      )
                    : rasterCache == null
                    ? Center(
                        child: Text(
                          cacheError ?? 'Loading disk cache settings…',
                        ),
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: DefaultTextStyle.merge(
                          style: Theme.of(context).textTheme.bodySmall,
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 4,
                            children: [
                              if (target != null)
                                Tooltip(
                                  message: 'Center inside the rectangular lens frustum; terrain visibility unknown. Target does not lock camera orientation.',
                                  child: Text(
                                    '${state.target.label}: ${state.containsDirection(target.direction) ? 'inside' : 'outside'} FOV · alt ${target.altitude.toStringAsFixed(1)}° · offset ${state.targetAngularOffset!.toStringAsFixed(1)}°',
                                  ),
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
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: LayoutBuilder(
                          builder: (context, timelineBounds) {
                            final controls = Wrap(
                              spacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Icon(Icons.schedule, size: 20),
                                TextButton(
                                  onPressed: chooseTime,
                                  child: Text(
                                    'Edit ${clock.time == null ? 'UTC' : 'local'}: ${editingTime.toIso8601String().substring(0, 16).replaceAll('T', ' ')}',
                                  ),
                                ),
                                timeStep(-1),
                                timeStep(1),
                                IconButton(
                                  tooltip: playback == null
                                      ? 'Play time ($playbackSpeed simulated minutes per second)'
                                      : 'Pause time',
                                  icon: Icon(
                                    playback == null
                                        ? Icons.play_arrow
                                        : Icons.pause,
                                  ),
                                  onPressed:
                                      playback == null &&
                                          nextPlaybackTime.year > 2100
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
                              ],
                            );
                            final slider = TimeSlider(
                              state: state,
                              onChanged: update,
                            );
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    localTimeLabel(state.timestamp),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                ),
                                Text(
                                  clock.time == null
                                      ? 'Local time unavailable · Edit UTC instead'
                                      : 'Scrub the local day · Edit local date and time',
                                ),
                                timelineBounds.maxWidth >= 800
                                    ? Row(
                                        children: [
                                          controls,
                                          const SizedBox(width: 16),
                                          Expanded(child: slider),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [controls, slider],
                                      ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
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
