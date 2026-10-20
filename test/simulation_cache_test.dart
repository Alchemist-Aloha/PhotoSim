import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/models/simulation_state.dart';

void main() {
  test('expensive astronomy is computed once per immutable state', () {
    final state = SimulationState(
      timestamp: DateTime.utc(2026, 6, 21, 19),
      groundElevation: 1234,
    );
    expect(identical(state.sky, state.sky), isTrue);
    expect(identical(state.observerFrame, state.observerFrame), isTrue);
    expect(identical(state.galacticCenter, state.galacticCenter), isTrue);
    final moved = state.copyWith(
      timestamp: state.timestamp.add(const Duration(minutes: 5)),
    );
    expect(identical(moved.sky, state.sky), isFalse);
    expect(moved.sky.moon.azimuth, isNot(state.sky.moon.azimuth));
    expect(moved.observerFrame, isNot(same(state.observerFrame)));
    // Copies made only for presentation (clean preview) keep the same values but cache independently.
    final clean = state.copyWith(
      showConstellations: false,
      target: CelestialTarget.none,
    );
    expect(clean.sky.moon.direction, state.sky.moon.direction);
  });
}
