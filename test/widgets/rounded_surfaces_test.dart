import 'package:fl_clash/ui/color.dart';
import 'package:fl_clash/ui/surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('light backgrounds stay white while dark surfaces keep their roles', () {
    for (final brightness in Brightness.values) {
      for (final seed in [Colors.blue, Colors.green, Colors.pink]) {
        final scheme = seededColorScheme(
          seedColor: seed,
          brightness: brightness,
        );
        final theme = ThemeData(colorScheme: scheme).withAppSurfaces;
        expect(theme.colorScheme.primary, scheme.primary);
        expect(theme.colorScheme.onSurface, scheme.onSurface);
        expect(
          theme.scaffoldBackgroundColor,
          SurfaceLevel.page.colorOf(scheme),
        );
        expect(theme.cardTheme.color, SurfaceLevel.card.colorOf(scheme));
        if (brightness == Brightness.light) {
          expect(theme.scaffoldBackgroundColor, Colors.white);
          expect(theme.cardTheme.color, Colors.white);
          expect(theme.canvasColor, Colors.white);
          expect(theme.colorScheme.surface, Colors.white);
          expect(theme.colorScheme.surfaceBright, Colors.white);
          expect(SurfaceLevel.block.colorOf(scheme), isNot(Colors.white));
          expect(theme.colorScheme.raisedCardShadows, isNotEmpty);
        } else {
          expect(theme.colorScheme, scheme);
          expect(theme.cardTheme.color, isNot(theme.scaffoldBackgroundColor));
          expect(theme.colorScheme.raisedCardShadows, isEmpty);
        }
        expect(
          theme.colorScheme.chromeSurface,
          brightness == Brightness.light
              ? Colors.white
              : scheme.surfaceContainerLow,
        );
      }
    }
  });
}
