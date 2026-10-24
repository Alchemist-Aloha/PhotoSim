import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';

import '../models/simulation_state.dart';
import 'saved_plans.dart';

class AppSession {
  AppSession({
    required this.state,
    required this.cleanComposition,
    this.planName,
    this.workspace = 'map',
    this.inspectorVisible = true,
    this.timelineExpanded = false,
    this.calendarWeekView = false,
    this.mapGuideDismissed = false,
    this.cleanPreview = false,
    this.playbackSpeed = 5,
    this.calendarDate,
    this.mapCenter,
    this.mapZoom = 14,
    this.expandedSections = const {},
  });
  final SimulationState state;
  final String cleanComposition;
  final String? planName;
  final String workspace;
  final bool inspectorVisible, timelineExpanded, calendarWeekView, cleanPreview;
  final bool mapGuideDismissed;
  final int playbackSpeed;
  final DateTime? calendarDate;
  final LatLng? mapCenter;
  final double mapZoom;
  final Map<String, bool> expandedSections;

  String encode() => jsonEncode({
    'version': 1,
    'composition': SavedPlan('Session', state).toJson(),
    'cleanComposition': jsonDecode(cleanComposition),
    'planName': planName,
    'workspace': workspace,
    'inspectorVisible': inspectorVisible,
    'timelineExpanded': timelineExpanded,
    'calendarWeekView': calendarWeekView,
    'mapGuideDismissed': mapGuideDismissed,
    'cleanPreview': cleanPreview,
    'playbackSpeed': playbackSpeed,
    'calendarDate': calendarDate?.toIso8601String(),
    'mapCenter': mapCenter == null
        ? null
        : [mapCenter!.latitude, mapCenter!.longitude],
    'mapZoom': mapZoom,
    'expandedSections': expandedSections,
  });

  static AppSession decode(String source) {
    if (utf8.encode(source).length > SessionStore.maxBytes) {
      throw const FormatException('Session exceeds size limit');
    }
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      if (json['version'] != 1 || json['version'] is! int) {
        throw const FormatException('Session version');
      }
      final state = SavedPlan.decode(jsonEncode(json['composition'])).state;
      final clean = SavedPlan.decode(jsonEncode(json['cleanComposition']))
          .state;
      final workspace = json['workspace'] as String;
      if (!['map', 'simulation', 'calendar', 'export'].contains(workspace)) {
        throw const FormatException('Workspace');
      }
      final name = json['planName'] as String?;
      if (name != null && (name.trim().isEmpty || name.length > 80)) {
        throw const FormatException('Plan name');
      }
      final speed = json['playbackSpeed'] as int;
      if (![1, 5, 30, 60].contains(speed)) {
        throw const FormatException('Playback speed');
      }
      final zoom = (json['mapZoom'] as num).toDouble();
      if (!zoom.isFinite || zoom < 3 || zoom > 18) {
        throw const FormatException('Map zoom');
      }
      LatLng? center;
      if (json['mapCenter'] != null) {
        final values = json['mapCenter'] as List<dynamic>;
        if (values.length != 2) throw const FormatException('Map center');
        final lat = (values[0] as num).toDouble(),
            lon = (values[1] as num).toDouble();
        if (!lat.isFinite ||
            lat.abs() > 85.05112878 ||
            !lon.isFinite ||
            lon.abs() > 180) {
          throw const FormatException('Map center');
        }
        center = LatLng(lat, lon);
      }
      DateTime? date;
      if (json['calendarDate'] != null) {
        date = DateTime.parse(json['calendarDate'] as String);
        if (!date.isUtc ||
            date.toIso8601String() != json['calendarDate'] ||
            date != DateTime.utc(date.year, date.month, date.day) ||
            date.year < 1970 ||
            date.year > 2037) {
          throw const FormatException('Calendar date');
        }
      }
      final sections = (json['expandedSections'] as Map<String, dynamic>)
          .cast<String, bool>();
      if (sections.length > 32 || sections.keys.any((key) => key.length > 80)) {
        throw const FormatException('Inspector sections');
      }
      return AppSession(
        state: state,
        cleanComposition: SavedPlan('Composition', clean).encode(),
        planName: name,
        workspace: workspace,
        inspectorVisible: json['inspectorVisible'] as bool,
        timelineExpanded: json['timelineExpanded'] as bool,
        calendarWeekView: json['calendarWeekView'] as bool,
        mapGuideDismissed: json.containsKey('mapGuideDismissed')
            ? json['mapGuideDismissed'] as bool
            : false,
        cleanPreview: json['cleanPreview'] as bool,
        playbackSpeed: speed,
        calendarDate: date,
        mapCenter: center,
        mapZoom: zoom,
        expandedSections: Map<String, bool>.from(sections),
      );
    } on Object {
      throw const FormatException('Invalid app session');
    }
  }
}

/// Small local checkpoint, separate from named plans.
// shortcut: one running app owns this checkpoint; add locking before supporting concurrent sessions.
class SessionStore {
  SessionStore(this.file);
  static const maxBytes = 64 * 1024;
  final File file;

  Future<({AppSession? session, String? warning})> restore() async {
    try {
      if (await file.length() > maxBytes) {
        throw const FormatException('Oversized session');
      }
      return (
        session: AppSession.decode(await file.readAsString()),
        warning: null,
      );
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      // ENOENT / Windows path-not-found are first launch; permission failures must disable autosave.
      if (code == 2 || (Platform.isWindows && code == 3)) {
        return (session: null, warning: null);
      }
      rethrow;
    } on FormatException {
      // Keep the damaged checkpoint for recovery instead of silently overwriting it.
      final quarantine = await file.parent.createTemp('unreadable-session-');
      await file.rename('${quarantine.path}/session.json');
      return (
        session: null,
        warning:
            'Previous session was unreadable and has been kept in ${quarantine.path}. Starting with defaults.',
      );
    }
  }

  void save(String source) {
    AppSession.decode(source);
    file.parent.createSync(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      temporary.writeAsStringSync(source, flush: true);
      temporary.renameSync(file.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
}
