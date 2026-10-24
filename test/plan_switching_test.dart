import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/app/app.dart';
import 'package:photosim/data/saved_plans.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/camera_inspector.dart';
import 'package:photosim/ui/map_workspace.dart';

class MemoryPlans extends PlanRepository {
  MemoryPlans() : super(Directory('/unused'));
  final destination = SavedPlan(
    'Mountain morning',
    SimulationState(focalLength: 85, timestamp: DateTime.utc(2026, 6, 21, 12)),
  );
  final saved = <SavedPlan>[];
  bool failSave = false, failLoad = false;
  Completer<File>? pendingSave;

  @override
  Future<File> save(SavedPlan plan) async {
    if (failSave) throw const FileSystemException('Disk full');
    saved.add(plan);
    return pendingSave == null
        ? File('/unused/snapshot.json')
        : await pendingSave!.future;
  }

  @override
  Future<({List<SavedPlan> plans, int unreadable})> loadAll() async {
    if (failLoad) throw const FileSystemException('Permission denied');
    return (plans: [destination], unreadable: 0);
  }
}

void main() {
  for (final action in [
    'Cancel',
    'Discard changes',
    'Save changes',
    'cancel save',
    'failed save',
    'concurrent edit',
  ]) {
    testWidgets('opening a plan protects changes: $action', (tester) async {
      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryPlans()..failSave = action == 'failed save';
      if (action == 'concurrent edit') store.pendingSave = Completer<File>();
      await tester.pumpWidget(PhotoSimApp(plans: store));
      CameraInspector inspector() =>
          tester.widget<CameraInspector>(find.byType(CameraInspector));
      final original = inspector().state.copyWith(
        focalLength: 50,
        latitude: action == 'failed save' ? 35.68 : null,
      );
      inspector().onChanged(original);
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      if (action == 'failed save') {
        expect(find.text('Camera moved'), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Photography plans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mountain morning'));
      await tester.pumpAndSettle();
      expect(
        find.text('Save changes before opening another plan?'),
        findsOneWidget,
      );
      expect(inspector().state, same(original));
      await tester.tap(
        find.text(
          ['Cancel', 'Discard changes'].contains(action)
              ? action
              : 'Save changes',
        ),
      );
      await tester.pumpAndSettle();
      if (action == 'cancel save') {
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      } else if ([
        'Save changes',
        'failed save',
        'concurrent edit',
      ].contains(action)) {
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextFormField),
          ),
          'Evening composition',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        if (action == 'concurrent edit') {
          inspector().onChanged(original.copyWith(focalLength: 100));
          await tester.pump();
          store.pendingSave!.complete(File('/unused/snapshot.json'));
          await tester.pumpAndSettle();
        }
      }
      if (['Discard changes', 'Save changes'].contains(action)) {
        expect(inspector().state, same(store.destination.state));
        expect(find.text('Saved · Mountain morning'), findsOneWidget);
      } else {
        expect(
          inspector().state.focalLength,
          action == 'concurrent edit' ? 100 : 50,
        );
        expect(find.text('Unsaved changes'), findsOneWidget);
      }
      if (['Save changes', 'concurrent edit'].contains(action)) {
        expect(store.saved.single.name, 'Evening composition');
        expect(store.saved.single.state, same(original));
      }
      if (action == 'failed save') {
        expect(
          find.textContaining('Check storage space and folder permissions'),
          findsOneWidget,
        );
        expect(find.textContaining('Disk full'), findsNothing);
        expect(store.saved, isEmpty);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(390, 844), const Size(1600, 960)]) {
    testWidgets(
      'plan listing errors preempt camera undo and preserve edits at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final store = MemoryPlans()..failLoad = true;
        await tester.pumpWidget(PhotoSimApp(plans: store));
        MapWorkspace map() =>
            tester.widget<MapWorkspace>(find.byType(MapWorkspace));
        final before = map().state;
        final moved = before.copyWith(
          latitude: before.latitude + 0.001,
          focalLength: 50,
        );
        map().onChanged(moved);
        map().onMoveCompleted!(before);
        await tester.pumpAndSettle();
        expect(find.text('Camera moved'), findsOneWidget);
        await tester.tap(find.byTooltip('Photography plans'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open plan'));
        await tester.pumpAndSettle();
        expect(find.text('No saved plans found.'), findsNothing);
        expect(find.text('Camera moved'), findsNothing);
        expect(
          find.textContaining('Check storage space and folder permissions'),
          findsOneWidget,
        );
        expect(find.text('Unsaved changes'), findsOneWidget);
        expect(map().state, same(moved));
        store.failLoad = false;
        await tester.tap(find.byTooltip('Photography plans'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open plan'));
        await tester.pumpAndSettle();
        expect(find.text('Mountain morning'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(map().state, same(moved));
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'dirty status ignores derived terrain and clears when edits are reverted',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(PhotoSimApp(plans: MemoryPlans()));
      CameraInspector inspector() =>
          tester.widget<CameraInspector>(find.byType(CameraInspector));
      final original = inspector().state;
      inspector().onChanged(original.copyWith(groundElevation: 1200));
      await tester.pump();
      expect(find.text('New plan'), findsOneWidget);
      inspector().onChanged(original.copyWith(aperture: 4));
      await tester.pump();
      expect(find.text('Unsaved changes'), findsOneWidget);
      inspector().onChanged(original);
      await tester.pump();
      expect(find.text('New plan'), findsOneWidget);
      await tester.tap(find.byTooltip('Photography plans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mountain morning'));
      await tester.pumpAndSettle();
      expect(
        find.text('Save changes before opening another plan?'),
        findsNothing,
      );
      expect(inspector().state.focalLength, 85);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
