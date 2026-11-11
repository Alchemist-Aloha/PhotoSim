import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:photosim/models/simulation_state.dart';
import 'package:photosim/ui/map_workspace.dart';
import 'package:photosim/ui/place_search.dart';

import 'place_search_test.dart' show placeFeature, placeResponse;

Widget searchApp(http.Client client) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 480,
      child: PlaceSearch(httpClient: client, onSelected: (_) {}),
    ),
  ),
);

Future<void> settleSearch(WidgetTester tester) async {
  await tester.pump();
  // Dart's stream-cancellation future schedules outside the widget fake clock.
  await tester.runAsync(() async {});
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('explicit search dropdown centers map without moving camera', (
    tester,
  ) async {
    final state = SimulationState(timestamp: DateTime.utc(2026));
    LatLng? viewCenter;
    double? viewZoom;
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return placeResponse([placeFeature()]);
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapWorkspace(
            state: state,
            httpClient: client,
            onChanged: (_) => fail('Searching must not move the camera'),
            onMoveCompleted: (_) =>
                fail('Searching must not create camera undo'),
            onViewChanged: (center, zoom) {
              viewCenter = center;
              viewZoom = zoom;
            },
          ),
        ),
      ),
    );
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Chamonix');
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settleSearch(tester);
    expect(calls, 1);
    expect(find.byType(MenuItemButton), findsOneWidget);
    expect(find.text('Chamonix-Mont-Blanc'), findsOneWidget);
    await tester.tap(find.text('Chamonix-Mont-Blanc'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(viewCenter, const LatLng(45.923, 6.87));
    expect(viewZoom, 13);
    expect(
      tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!
          .camera
          .center,
      viewCenter,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Chamonix-Mont-Blanc',
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty input, empty results, loading, failure and retry', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<http.Response>();
    final client = MockClient((_) async {
      calls++;
      if (calls == 1) return placeResponse([]);
      if (calls == 2) return http.Response('Busy', 429);
      return pending.future;
    });
    addTearDown(client.close);
    await tester.pumpWidget(searchApp(client));
    await tester.tap(find.text('Search'));
    await tester.pump();
    expect(find.text('Enter a town or place to search.'), findsOneWidget);
    expect(calls, 0);
    await tester.enterText(find.byType(TextField), 'Nowhere');
    await tester.tap(find.text('Search'));
    await settleSearch(tester);
    expect(find.textContaining('No places found.'), findsOneWidget);
    await tester.tap(find.text('Search'));
    await settleSearch(tester);
    expect(find.textContaining('Place search unavailable.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Chamonix');
    await tester.tap(find.text('Search'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    pending.complete(placeResponse([placeFeature()]));
    await settleSearch(tester);
    expect(find.text('Chamonix-Mont-Blanc'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Paris');
    await tester.pumpAndSettle();
    expect(find.text('Chamonix-Mont-Blanc'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('search timeout cancels a stalled response body before retry', (
    tester,
  ) async {
    var calls = 0, cancelled = 0;
    final body = StreamController<List<int>>(onCancel: () => cancelled++);
    addTearDown(body.close);
    final client = MockClient.streaming((_, _) async {
      if (++calls > 1) {
        return http.StreamedResponse(
          Stream.value(placeResponse([]).bodyBytes),
          200,
        );
      }
      body.add([123]);
      return http.StreamedResponse(body.stream, 200);
    });
    addTearDown(client.close);
    await tester.pumpWidget(searchApp(client));
    await tester.enterText(find.byType(TextField), 'Town');
    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    await settleSearch(tester);
    expect(find.textContaining('Place search unavailable.'), findsOneWidget);
    expect(cancelled, 1);
    await tester.tap(find.text('Search'));
    await settleSearch(tester);
    expect(calls, 2);
    expect(find.textContaining('No places found.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeout and disposal during search are safe', (tester) async {
    final pending = Completer<http.Response>();
    final client = MockClient((_) => pending.future);
    addTearDown(client.close);
    await tester.pumpWidget(searchApp(client));
    await tester.enterText(find.byType(TextField), 'Town');
    await tester.tap(find.text('Search'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.textContaining('Place search unavailable.'), findsOneWidget);
    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(placeResponse([placeFeature()]));
    await settleSearch(tester);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 640),
    const Size(844, 390),
    const Size(800, 1280),
  ]) {
    testWidgets('dropdown scrolls and dismisses at $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final client = MockClient(
        (_) async => placeResponse([
          for (var i = 0; i < 5; i++) placeFeature(name: 'Town $i'),
        ]),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 480,
                child: PlaceSearch(httpClient: client, onSelected: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Town');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settleSearch(tester);
      await tester.ensureVisible(find.text('Town 4'));
      await tester.pumpAndSettle();
      expect(find.text('Town 4').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(find.byType(PlaceSearch), findsOneWidget);
      await tester.tap(find.text('Search'));
      await settleSearch(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(find.byType(PlaceSearch), findsOneWidget);
      await tester.tap(find.text('Search'));
      await settleSearch(tester);
      await tester.tapAt(Offset(size.width - 8, size.height - 8));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
