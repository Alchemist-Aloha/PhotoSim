import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../data/saved_plans.dart';
import '../data/app_session.dart';
import '../data/raster_cache.dart';
import '../data/night_conditions.dart';
import '../ui/night_calendar.dart';

import '../core/local_time.dart';
import '../core/night_sky.dart';

import '../models/simulation_state.dart';
import '../ui/camera_inspector.dart';
import '../ui/map_workspace.dart';
import '../ui/simulation_workspace.dart';
import '../ui/time_slider.dart';

class PhotoSimApp extends StatelessWidget {
  const PhotoSimApp({
    super.key,
    this.plans,
    this.rasterCache,
    this.sessionStore,
    this.initialSession,
    this.sessionWarning,
  });
  final PlanRepository? plans;
  final RasterCache? rasterCache;
  final SessionStore? sessionStore;
  final AppSession? initialSession;
  final String? sessionWarning;

  @override
  Widget build(BuildContext context) {
    ThemeData materialTheme(Brightness brightness) {
      final dark = brightness == Brightness.dark;
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF287E73),
          brightness: brightness,
          surface: Color(dark ? 0xFF141A1C : 0xFFF7F9F8),
          surfaceDim: Color(dark ? 0xFF101618 : 0xFFD5DDD9),
          surfaceBright: Color(dark ? 0xFF3A4345 : 0xFFF7F9F8),
          surfaceContainerLowest: Color(dark ? 0xFF0F1517 : 0xFFFFFFFF),
          surfaceContainerLow: Color(dark ? 0xFF1B2224 : 0xFFF0F4F2),
          surfaceContainer: Color(dark ? 0xFF20282A : 0xFFEAF0ED),
          surfaceContainerHigh: Color(dark ? 0xFF293133 : 0xFFE3EBE7),
          surfaceContainerHighest: Color(dark ? 0xFF343C3E : 0xFFDDE5E1),
        ),
        fontFamily: 'Source Sans 3',
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      );
      return theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          titleLarge: theme.textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.w600,
          ),
          titleMedium: theme.textTheme.titleMedium!.copyWith(
            fontWeight: FontWeight.w600,
          ),
          titleSmall: theme.textTheme.titleSmall!.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'PhotoSim',
      debugShowCheckedModeBanner: false,
      theme: materialTheme(Brightness.light),
      darkTheme: materialTheme(Brightness.dark),
      themeMode: defaultTargetPlatform == TargetPlatform.android
          ? ThemeMode.system
          : ThemeMode.dark,
      home: WorkspaceShell(
        plans: plans,
        rasterCache: rasterCache,
        sessionStore: sessionStore,
        initialSession: initialSession,
        sessionWarning: sessionWarning,
      ),
    );
  }
}

enum Workspace { map, simulation, calendar, export }

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    super.key,
    this.plans,
    this.rasterCache,
    this.sessionStore,
    this.initialSession,
    this.sessionWarning,
  });
  final PlanRepository? plans;
  final RasterCache? rasterCache;
  final SessionStore? sessionStore;
  final AppSession? initialSession;
  final String? sessionWarning;

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell>
    with WidgetsBindingObserver {
  // Keep service cooldowns/connections alive across Map/3D workspace recreation.
  final terrainClient = http.Client();
  SimulationState state = SimulationState(
    renderQuality: Platform.isAndroid
        ? RenderQuality.performance
        : RenderQuality.balanced,
  );
  Workspace workspace = Workspace.map;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool inspectorVisible = true;
  bool timelineExpanded = false;
  bool calendarWeekView = false;
  bool mapGuideDismissed = false;
  late final nightConditions = NightConditionsRepository(terrainClient);
  bool cleanPreview = false;
  RasterCache? rasterCache;
  String? cacheError;
  DateTime? calendarDate;
  LatLng? mapCenter;
  double mapZoom = 14;
  Map<String, bool> expandedSections = {};
  Timer? sessionTimer;
  AppLifecycleListener? exitListener;
  String? lastSession, sessionWarning;
  bool disposing = false;

  AppSession get session => AppSession(
    state: state,
    cleanComposition: cleanComposition,
    planName: currentPlanName,
    workspace: workspace.name,
    inspectorVisible: inspectorVisible,
    timelineExpanded: timelineExpanded,
    calendarWeekView: calendarWeekView,
    mapGuideDismissed: mapGuideDismissed,
    cleanPreview: cleanPreview,
    playbackSpeed: playbackSpeed,
    calendarDate: calendarDate,
    mapCenter: mapCenter,
    mapZoom: mapZoom,
    expandedSections: expandedSections,
  );

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    scheduleSessionSave();
  }

  void scheduleSessionSave() {
    if (widget.sessionStore == null || disposing || sessionTimer != null) {
      return;
    }
    sessionTimer = Timer(const Duration(milliseconds: 500), () {
      sessionTimer = null;
      saveSession();
    });
  }

  bool saveSession() {
    sessionTimer?.cancel();
    sessionTimer = null;
    final store = widget.sessionStore;
    if (store == null) return sessionWarning == null;
    try {
      final source = session.encode();
      if (source != lastSession) store.save(source);
      lastSession = source;
      if (!disposing && mounted && sessionWarning != null) {
        super.setState(() => sessionWarning = null);
      }
      return true;
    } on Object {
      const warning =
          'Session could not be saved. Check storage space and permissions; your previous checkpoint is unchanged.';
      if (!disposing && mounted && sessionWarning != warning) {
        super.setState(() => sessionWarning = warning);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..removeCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: const Text(warning),
                action: SnackBarAction(label: 'Retry', onPressed: saveSession),
              ),
            );
        });
      }
      return false;
    }
  }

  Future<AppExitResponse> requestExit() async {
    if (saveSession()) return AppExitResponse.exit;
    if (!mounted) return AppExitResponse.cancel;
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session could not be saved'),
        content: const Text(
          'Check storage space and permissions. Exit without preserving the latest changes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Exit without saving'),
          ),
        ],
      ),
    );
    return exit == true ? AppExitResponse.exit : AppExitResponse.cancel;
  }

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
      // Publish immediately so GPU/world setup can overlap disk indexing; cache
      // operations still queue behind initialize inside RasterCache.
      if (mounted && rasterCache == null) setState(() => rasterCache = cache);
      await cache.initialize();
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
      if (Platform.isAndroid) {
        await SystemChrome.setEnabledSystemUIMode(
          value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        );
      } else {
        await const MethodChannel('photosim/window')
            .invokeMethod<void>('fullscreen', value);
      }
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
    // A save confirmation outranks the transient undo prompt; without this the
    // messenger queues it behind that snackbar's ten-second duration.
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
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
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          setState(() {
            state = selected.state;
            cleanComposition = composition;
            currentPlanName = selected.name;
            workspace = Workspace.map;
            calendarDate = null;
            mapCenter = null;
            mapZoom = 14;
            openedPlan++;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
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
    final saved = widget.initialSession;
    if (saved != null) {
      state = saved.state;
      workspace = Workspace.values.byName(saved.workspace);
      inspectorVisible = saved.inspectorVisible;
      timelineExpanded = saved.timelineExpanded;
      calendarWeekView = saved.calendarWeekView;
      mapGuideDismissed = saved.mapGuideDismissed;
      playbackSpeed = saved.playbackSpeed;
      currentPlanName = saved.planName;
      calendarDate = saved.calendarDate;
      mapCenter = saved.mapCenter;
      mapZoom = saved.mapZoom;
      expandedSections = Map.of(saved.expandedSections);
    }
    cleanComposition = saved?.cleanComposition ?? composition;
    sessionWarning = widget.sessionWarning;
    if (widget.sessionStore != null || widget.sessionWarning != null) {
      exitListener = AppLifecycleListener(onExitRequested: requestExit);
      scheduleSessionSave();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (saved?.cleanPreview == true) unawaited(setCleanPreview(true));
      if (widget.sessionWarning != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.sessionWarning!)));
      }
      // Map and calendar do not need the disk index on their startup path.
      if (workspace == Workspace.simulation || workspace == Workspace.export) {
        unawaited(initializeCache());
      }
    });
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
    if (lifecycle != AppLifecycleState.resumed) {
      if (playback != null) setState(stopPlayback);
      saveSession();
    }
  }

  @override
  void dispose() {
    disposing = true;
    saveSession();
    exitListener?.dispose();
    terrainClient.close();
    stopPlayback();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void update(SimulationState next) => setState(() {
    if (next.timestamp != state.timestamp) stopPlayback();
    state = next;
  });

  void updateFromInspector(SimulationState next) {
    final before = state;
    final moved = before.location != next.location;
    if (moved) {
      mapCenter = next.location;
      openedPlan++;
    }
    update(next);
    if (moved) offerCameraUndo(before);
  }

  void offerCameraUndo(SimulationState before) {
    final after = state;
    if (before.location == after.location && before.azimuth == after.azimuth) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Camera moved'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            final locationChanged = before.location != after.location;
            if (locationChanged) {
              mapCenter = before.location;
              openedPlan++;
            }
            update(
              state.copyWith(
                latitude: locationChanged ? before.latitude : null,
                longitude: locationChanged ? before.longitude : null,
                azimuth: before.azimuth != after.azimuth
                    ? before.azimuth
                    : null,
                fixedElevation: locationChanged ? before.fixedElevation : null,
                clearFixedElevation:
                    locationChanged && before.fixedElevation == null,
              ),
            );
          },
        ),
      ),
    );
  }

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

  void aimAtTarget() {
    final target = state.targetPosition;
    if (target != null) {
      update(state.copyWith(azimuth: target.azimuth, pitch: target.altitude));
    }
  }

  Widget timeline(bool compact) {
    final clock = localClock(
      timestamp: state.timestamp,
      latitude: state.latitude,
      longitude: state.longitude,
    );
    final editingTime = clock.time ?? state.timestamp;
    final target = state.targetPosition;
    final sky = state.sky;
    final readouts = Wrap(
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
          'Moon az ${sky.moon.azimuth.toStringAsFixed(1)}° · alt ${sky.moon.altitude.toStringAsFixed(1)}° · ${(sky.moonIllumination * 100).toStringAsFixed(0)}% ${sky.moonWaxing ? 'waxing' : 'waning'}',
        ),
      ],
    );
    final edit = TextButton(
      onPressed: chooseTime,
      child: Text(
        compact
            ? 'Edit ${clock.time == null ? 'UTC' : 'local (${clock.time!.timeZoneName})'}\n${editingTime.toIso8601String().substring(0, 16).replaceAll('T', ' ')}'
            : 'Edit ${clock.time == null ? 'UTC' : 'local'}: ${editingTime.toIso8601String().substring(0, 16).replaceAll('T', ' ')}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final play = IconButton(
      tooltip: playback == null
          ? 'Play time ($playbackSpeed simulated minutes per second)'
          : 'Pause time',
      icon: Icon(playback == null ? Icons.play_arrow : Icons.pause),
      onPressed: playback == null && nextPlaybackTime.year > 2100
          ? null
          : togglePlayback,
    );
    final speed = PopupMenuButton<int>(
      tooltip: 'Playback speed',
      icon: const Icon(Icons.speed),
      initialValue: playbackSpeed,
      itemBuilder: (_) => [
        for (final value in [1, 5, 30, 60])
          PopupMenuItem(value: value, child: Text('$value min/s')),
      ],
      onSelected: (value) => setState(() => playbackSpeed = value),
    );
    final slider = TimeSlider(state: state, onChanged: update);
    final controls = Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.schedule, size: 20),
        edit,
        timeStep(-1),
        timeStep(1),
        play,
        speed,
      ],
    );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 16,
          vertical: 4,
        ),
        child: compact
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: edit),
                      play,
                      IconButton(
                        tooltip: timelineExpanded
                            ? 'Collapse timeline details'
                            : 'Expand timeline details',
                        onPressed: () => setState(
                          () => timelineExpanded = !timelineExpanded,
                        ),
                        icon: Icon(
                          timelineExpanded
                              ? Icons.expand_more
                              : Icons.expand_less,
                        ),
                      ),
                    ],
                  ),
                  slider,
                  if (timelineExpanded)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.25,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localTimeLabel(state.timestamp),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Wrap(children: [timeStep(-1), timeStep(1), speed]),
                            DefaultTextStyle.merge(
                              style: Theme.of(context).textTheme.bodySmall,
                              child: readouts,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.bodySmall,
                    child: readouts,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    localTimeLabel(state.timestamp),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    clock.time == null
                        ? 'Local time unavailable · Edit UTC instead'
                        : 'Scrub the local day · Edit local date and time',
                  ),
                  LayoutBuilder(
                    builder: (context, bounds) =>
                        bounds.maxWidth >=
                            1000 *
                                MediaQuery.textScalerOf(context).scale(16) /
                                16
                        ? Row(
                            children: [
                              controls,
                              const SizedBox(width: 16),
                              Expanded(child: slider),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [controls, slider],
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    final dockedInspector = size.width >= 1000;
    final compactTimeline = compact || size.height < 600;
    final editingScene =
        workspace == Workspace.map || workspace == Workspace.simulation;
    final inspector = CameraInspector(
      state: state,
      onChanged: updateFromInspector,
      rasterCache: rasterCache,
      cacheError: cacheError,
      expandedSections: expandedSections,
      onSectionChanged: (title, expanded) =>
          setState(() => expandedSections[title] = expanded),
    );
    void changeWorkspace(int index) {
      setState(() {
        if (Workspace.values[index] == Workspace.calendar ||
            Workspace.values[index] == Workspace.export) {
          stopPlayback();
        }
        workspace = Workspace.values[index];
      });
      if ((workspace == Workspace.simulation ||
              workspace == Workspace.export) &&
          rasterCache == null &&
          cacheError == null) {
        unawaited(initializeCache());
      }
    }

    void showInspector() {
      if (dockedInspector) {
        setState(() => inspectorVisible = !inspectorVisible);
      } else {
        scaffoldKey.currentState?.openEndDrawer();
      }
    }

    final viewport = workspace == Workspace.calendar
        ? NightCalendar(
            state: state,
            weekView: calendarWeekView,
            repository: nightConditions,
            initialDate: calendarDate,
            onDateChanged: (date) => setState(() => calendarDate = date),
            onPreview: (utc) {
              final next = state.copyWith(
                timestamp: utc,
                target: CelestialTarget.none,
              );
              final aim = ObserverSkyFrame(
                timestamp: utc,
                latitude: next.latitude,
                longitude: next.longitude,
              ).lowMilkyWayAim(next.azimuth);
              setState(() {
                stopPlayback();
                state = next.copyWith(
                  azimuth: aim.azimuth,
                  pitch: aim.altitude,
                );
                workspace = Workspace.simulation;
              });
            },
          )
        : workspace == Workspace.map
        ? MapWorkspace(
            key: ValueKey(openedPlan),
            state: state,
            initialCenter: mapCenter,
            initialZoom: mapZoom,
            guideDismissed: mapGuideDismissed,
            onGuideDismissedChanged: (value) =>
                setState(() => mapGuideDismissed = value),
            onMoveCompleted: offerCameraUndo,
            onViewChanged: (center, zoom) {
              mapCenter = LatLng(
                center.latitude.clamp(-85.05112878, 85.05112878),
                (center.longitude + 180) % 360 - 180,
              );
              mapZoom = zoom.clamp(3, 18);
              scheduleSessionSave();
            },
            onChanged: update,
          )
        : rasterCache == null
        ? Center(child: Text(cacheError ?? 'Loading disk cache settings…'))
        : SimulationWorkspace(
            rasterCache: rasterCache,
            httpClient: terrainClient,
            state: state,
            cleanPreview: cleanPreview,
            exportMode: workspace == Workspace.export,
            onChanged: update,
            onGroundElevationChanged: (location, elevation) {
              if (state.location == location) {
                update(state.copyWith(groundElevation: elevation));
              }
            },
            onPausePlayback: () => setState(stopPlayback),
          );
    final scaffold = Scaffold(
      key: scaffoldKey,
      floatingActionButton: cleanPreview
          ? FloatingActionButton(
              tooltip: 'Exit fullscreen preview (Esc)',
              onPressed: () => setCleanPreview(false),
              child: const Icon(Icons.fullscreen_exit),
            )
          : null,
      appBar: cleanPreview
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workspace == Workspace.calendar
                        ? 'Night calendar'
                        : workspace == Workspace.export
                        ? 'Export'
                        : 'PhotoSim',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                if (sessionWarning != null)
                  IconButton(
                    tooltip: 'Session recovery warning',
                    icon: const Icon(Icons.warning_amber),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(sessionWarning!),
                        action: widget.sessionStore == null
                            ? null
                            : SnackBarAction(
                                label: 'Retry',
                                onPressed: saveSession,
                              ),
                      ),
                    ),
                  ),
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
                if (workspace == Workspace.calendar)
                  IconButton(
                    tooltip: calendarWeekView
                        ? 'Switch to month view'
                        : 'Switch to week view',
                    onPressed: () =>
                        setState(() => calendarWeekView = !calendarWeekView),
                    icon: Icon(
                      calendarWeekView
                          ? Icons.calendar_view_month
                          : Icons.calendar_view_week,
                    ),
                  ),
                if (!compact && editingScene) ...[
                  PopupMenuButton<CelestialTarget>(
                    tooltip: 'Select astronomical target',
                    icon: const Icon(Icons.track_changes),
                    initialValue: state.target,
                    itemBuilder: (_) => [
                      for (final target in CelestialTarget.values)
                        PopupMenuItem(value: target, child: Text(target.label)),
                    ],
                    onSelected: (value) =>
                        update(state.copyWith(target: value)),
                  ),
                  IconButton(
                    tooltip: 'Aim at selected target',
                    icon: const Icon(Icons.gps_fixed),
                    onPressed: state.targetPosition == null
                        ? null
                        : aimAtTarget,
                  ),
                  IconButton(
                    tooltip: 'Fullscreen preview',
                    icon: const Icon(Icons.fullscreen),
                    onPressed: workspace == Workspace.simulation
                        ? () => setCleanPreview(true)
                        : null,
                  ),
                ],
                if (editingScene)
                  IconButton(
                    tooltip: dockedInspector
                        ? 'Toggle camera inspector'
                        : 'Camera controls',
                    onPressed: showInspector,
                    icon: const Icon(Icons.tune),
                  ),
                if (compact && editingScene)
                  PopupMenuButton<Object>(
                    tooltip: 'More options',
                    itemBuilder: (_) => [
                      for (final target in CelestialTarget.values)
                        CheckedPopupMenuItem<Object>(
                          value: target,
                          checked: state.target == target,
                          child: Text(target.label),
                        ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'aim',
                        enabled: state.targetPosition != null,
                        child: const Text('Aim at selected target'),
                      ),
                      PopupMenuItem(
                        value: 'fullscreen',
                        enabled: workspace == Workspace.simulation,
                        child: const Text('Fullscreen preview'),
                      ),
                    ],
                    onSelected: (value) {
                      if (value is CelestialTarget) {
                        update(state.copyWith(target: value));
                      } else if (value == 'aim') {
                        aimAtTarget();
                      } else if (value == 'fullscreen') {
                        unawaited(setCleanPreview(true));
                      }
                    },
                  ),
              ],
            ),
      endDrawer: dockedInspector || cleanPreview || !editingScene
          ? null
          : Drawer(
              width: size.width < 400 ? size.width : 400,
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        8,
                        8,
                        8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Camera controls',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close camera controls',
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                scaffoldKey.currentState?.closeEndDrawer(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: inspector),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: cleanPreview || !compact
          ? null
          : NavigationBar(
              selectedIndex: workspace.index,
              onDestinationSelected: changeWorkspace,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: 'Map',
                ),
                NavigationDestination(
                  icon: Icon(Icons.landscape_outlined),
                  selectedIcon: Icon(Icons.landscape),
                  label: '3D Preview',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Calendar',
                ),
                NavigationDestination(
                  icon: Icon(Icons.ios_share_outlined),
                  selectedIcon: Icon(Icons.ios_share),
                  label: 'Export',
                ),
              ],
            ),
      body: SafeArea(
        top: false,
        child: Row(
          children: [
            if (!cleanPreview && !compact) ...[
              NavigationRail(
                selectedIndex: workspace.index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: changeWorkspace,
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
                  NavigationRailDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    selectedIcon: Icon(Icons.calendar_month),
                    label: Text('Calendar'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.ios_share_outlined),
                    selectedIcon: Icon(Icons.ios_share),
                    label: Text('Export'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: viewport),
                        if (!cleanPreview &&
                            editingScene &&
                            dockedInspector &&
                            inspectorVisible) ...[
                          const VerticalDivider(width: 1),
                          SizedBox(width: 310, child: inspector),
                        ],
                      ],
                    ),
                  ),
                  if (!cleanPreview && editingScene) ...[
                    const Divider(height: 1),
                    timeline(compactTimeline),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return PopScope(
      canPop: !cleanPreview,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && cleanPreview) unawaited(setCleanPreview(false));
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (cleanPreview) unawaited(setCleanPreview(false));
          },
        },
        child: Focus(autofocus: true, child: scaffold),
      ),
    );
  }
}
