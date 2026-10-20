import 'package:fl_clash/ui/color.dart';
import 'package:fl_clash/ui/surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('official schemes and surface roles remain unchanged', () {
    for (final brightness in Brightness.values) {
      for (final seed in [Colors.blue, Colors.green, Colors.pink]) {
        final scheme = seededColorScheme(
          seedColor: seed,
          brightness: brightness,
        );
        final theme = ThemeData(colorScheme: scheme).withAppSurfaces;
        expect(theme.colorScheme, scheme);
        expect(
          theme.scaffoldBackgroundColor,
          SurfaceLevel.page.colorOf(scheme),
        );
        expect(theme.cardTheme.color, SurfaceLevel.card.colorOf(scheme));
        expect(theme.cardTheme.color, isNot(theme.scaffoldBackgroundColor));
        expect(
          theme.colorScheme.chromeSurface,
          brightness == Brightness.light
              ? scheme.surfaceContainerHighest
              : scheme.surfaceContainerLow,
        );
      }
    }
  });
}
