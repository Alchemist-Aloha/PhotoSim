import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosim/app/app.dart';

void main() {
  testWidgets('shared themes keep type roles and accessible color pairs', (
    tester,
  ) async {
    await tester.pumpWidget(const PhotoSimApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    for (final theme in [app.theme!, app.darkTheme!]) {
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Source Sans 3');
      expect(theme.textTheme.titleLarge!.fontWeight, FontWeight.w600);
      expect(theme.textTheme.titleMedium!.fontWeight, FontWeight.w600);
      expect(theme.textTheme.titleSmall!.fontWeight, FontWeight.w600);
      final colors = theme.colorScheme;
      for (final (foreground, background) in [
        (colors.onPrimary, colors.primary),
        (colors.onPrimaryContainer, colors.primaryContainer),
        (colors.onSecondary, colors.secondary),
        (colors.onSecondaryContainer, colors.secondaryContainer),
        (colors.onTertiary, colors.tertiary),
        (colors.onTertiaryContainer, colors.tertiaryContainer),
        (colors.onError, colors.error),
        (colors.onErrorContainer, colors.errorContainer),
        for (final surface in [
          colors.surface,
          colors.surfaceDim,
          colors.surfaceBright,
          colors.surfaceContainerLowest,
          colors.surfaceContainerLow,
          colors.surfaceContainer,
          colors.surfaceContainerHigh,
          colors.surfaceContainerHighest,
        ]) ...[
          (colors.onSurface, surface),
          (colors.onSurfaceVariant, surface),
          (colors.primary, surface),
        ],
      ]) {
        final a = foreground.computeLuminance();
        final b = background.computeLuminance();
        final contrast = a > b
            ? (a + 0.05) / (b + 0.05)
            : (b + 0.05) / (a + 0.05);
        expect(
          contrast,
          greaterThanOrEqualTo(4.5),
          reason: '${theme.brightness}: $foreground on $background',
        );
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  test('all used font weights are bundled for offline startup', () async {
    for (final weight in ['Regular', 'Medium', 'Semibold', 'Bold']) {
      final font = await rootBundle.load(
        'assets/fonts/SourceSans3-$weight.ttf',
      );
      expect(font.getUint32(0), 0x00010000);
    }
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
    expect(license, contains('Adobe'));
  });
}
