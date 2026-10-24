import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/data/app_session.dart';
import 'package:photosim/data/raster_cache.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/ui/night_calendar.dart';
import 'package:photosim/ui/map_workspace.dart';

import 'app_session_test.dart' show sessionFixture;
import 'night_calendar_test.dart' show settleCalendar;

void main() {
  late Directory support;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    support = Directory.systemTemp.createTempSync('photosim-session-support-');
    // Start the cache worker outside the widget test's fake async zone.
    BuiltInMapCachingProvider.getOrCreateInstance(cacheDirectory: support.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => support.path);
  });
  tearDown(() async {
    // flutter_map keeps its process-wide disk-cache worker alive between maps.
    await BuiltInMapCachingProvider.getOrCreateInstance().destroy();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await support.exists()) await support.delete(recursive: true);
  });
  testWidgets(
    'immediate exit checkpoints edits and restores UI, map framing and calendar date',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = Directory.systemTemp.createTempSync('photosim-session-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = SessionStore(File('${dir.path}/session.json'));
      final initial = sessionFixture(workspace: 'map', inspectorVisible: true);
      final cache = RasterCache(Directory('${dir.path}/cache'));
      await tester.pumpWidget(
        PhotoSimApp(
          sessionStore: store,
          initialSession: initial,
          rasterCache: cache,
        ),
      );
      final inspector = tester.widget<CameraInspector>(
        find.byType(CameraInspector),
      );
      final edited = inspector.state.copyWith(
        latitude: 35.68,
        longitude: 139.69,
        focalLength: 135,
        timestamp: DateTime.utc(2026, 7, 15, 5),
      );
      inspector.onChanged(edited);
      inspector.onSectionChanged!('Exposure', true);
      await tester.pump();
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      map.mapController!.move(const LatLng(35.7, 139.8), 17);
      await tester.pump();
      await tester.tap(find.text('Calendar'));
      await settleCalendar(tester);
      final selected = DateTime.utc(2026, 9, 17);
      tester.widget<NightCalendar>(find.byType(NightCalendar)).onDateChanged!(
        selected,
      );
      await tester.pumpWidget(const SizedBox());
      final saved = (await tester.runAsync(store.restore))!.session!;
      expect(
        SavedPlan('Session', saved.state).encode(),
        SavedPlan('Session', edited).encode(),
      );
      expect(saved.workspace, 'calendar');
      expect(saved.calendarWeekView, isTrue);
      expect(saved.mapGuideDismissed, isTrue);
      expect(saved.calendarDate, selected);
      expect(saved.mapCenter, const LatLng(35.7, 139.8));
      expect(saved.mapZoom, 17);
      expect(saved.expandedSections['Exposure'], isTrue);
      expect(saved.cleanComposition, initial.cleanComposition);
      await tester.pumpWidget(
        PhotoSimApp(
          sessionStore: SessionStore(store.file),
          initialSession: saved,
          rasterCache: cache,
        ),
      );
      await settleCalendar(tester);
      final calendar = tester.widget<NightCalendar>(find.byType(NightCalendar));
      expect(calendar.weekView, isTrue);
      expect(calendar.initialDate, selected);
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      final restored = tester.widget<CameraInspector>(
        find.byType(CameraInspector),
      );
      expect(restored.state.timestamp, edited.timestamp);
      expect(restored.state.location, edited.location);
      expect(restored.state.focalLength, 135);
      expect(restored.expandedSections['Exposure'], isTrue);
      expect(
        tester.widget<MapWorkspace>(find.byType(MapWorkspace)).guideDismissed,
        isTrue,
      );
      final restoredMap = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!
          .camera;
      expect(restoredMap.center, saved.mapCenter);
      expect(restoredMap.zoom, 17);
      expect(
        find.byTooltip('Play time (30 simulated minutes per second)'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed exit checkpoint asks before discarding changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = File('${support.path}/session.json');
    final store = SessionStore(file);
    final original = sessionFixture(workspace: 'map', inspectorVisible: true);
    store.save(original.encode());
    Directory('${file.path}.tmp').createSync();
    await tester.pumpWidget(
      PhotoSimApp(
        sessionStore: store,
        initialSession: original,
        rasterCache: RasterCache(Directory('${support.path}/cache')),
      ),
    );
    final inspector = tester.widget<CameraInspector>(
      find.byType(CameraInspector),
    );
    inspector.onChanged(inspector.state.copyWith(focalLength: 135));
    await tester.pump();
    final cancelled = tester.binding.handleRequestAppExit();
    await tester.pumpAndSettle();
    expect(find.text('Session could not be saved'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    expect(await cancelled, AppExitResponse.cancel);
    await tester.pumpAndSettle();
    final approved = tester.binding.handleRequestAppExit();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exit without saving'));
    expect(await approved, AppExitResponse.exit);
    expect(file.readAsStringSync(), original.encode());
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'startup storage failure also requires consent to exit without recovery',
    (tester) async {
      await tester.pumpWidget(
        PhotoSimApp(
          sessionWarning: 'Session storage is unavailable.',
          rasterCache: RasterCache(Directory('${support.path}/cache')),
        ),
      );
      final response = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      expect(find.text('Session could not be saved'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      expect(await response, AppExitResponse.cancel);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(390, 844), const Size(1600, 960)]) {
    testWidgets('checkpoint errors preempt camera undo and retry at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = SessionStore(File('${support.path}/session.json'));
      final original = sessionFixture(workspace: 'map', inspectorVisible: true);
      store.save(original.encode());
      await tester.pumpWidget(
        PhotoSimApp(
          sessionStore: store,
          initialSession: original,
          rasterCache: RasterCache(Directory('${support.path}/cache')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      final checkpoint = store.file.readAsStringSync();
      final blocked = Directory('${store.file.path}.tmp')..createSync();
      MapWorkspace map() =>
          tester.widget<MapWorkspace>(find.byType(MapWorkspace));
      final before = map().state;
      final moved = before.copyWith(
        latitude: before.latitude + 0.001,
        focalLength: 135,
      );
      map().onChanged(moved);
      map().onMoveCompleted!(before);
      await tester.pump();
      expect(find.text('Camera moved'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Session could not be saved. Check storage'),
        findsOneWidget,
      );
      expect(find.text('Camera moved'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byTooltip('Session recovery warning'), findsOneWidget);
      expect(map().state, same(moved));
      expect(store.file.readAsStringSync(), checkpoint);
      blocked.deleteSync();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Session recovery warning'), findsNothing);
      final saved = AppSession.decode(store.file.readAsStringSync());
      expect(
        SavedPlan('Session', saved.state).encode(),
        SavedPlan('Session', moved).encode(),
      );
      expect(saved.cleanComposition, original.cleanComposition);
      expect(map().state, same(moved));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'backgrounding flushes without waiting for autosave and save errors stay visible',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync(
        'photosim-session-pause-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = SessionStore(File('${dir.path}/session.json'));
      await tester.pumpWidget(
        PhotoSimApp(
          sessionStore: store,
          rasterCache: RasterCache(Directory('${dir.path}/cache')),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(store.file.existsSync(), isTrue);
      final before = store.file.readAsStringSync();
      Directory('${store.file.path}.tmp').createSync();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      // A no-op checkpoint needs no write; changing a UI preference makes one necessary.
      await tester.tap(find.text('Calendar'));
      await settleCalendar(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byTooltip('Session recovery warning'), findsOneWidget);
      expect(store.file.readAsStringSync(), before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
