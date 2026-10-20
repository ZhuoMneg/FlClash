import 'package:fl_clash/ui/color.dart';
import 'package:fl_clash/ui/surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test(
    'light surfaces match the cool white preview while dark stays themed',
    () {
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
          if (brightness == Brightness.light) {
            expect(theme.scaffoldBackgroundColor, Colors.white);
            expect(theme.cardTheme.color, const Color(0xFFFCFCFE));
            expect(theme.canvasColor, Colors.white);
            expect(SurfaceLevel.block.colorOf(scheme), const Color(0xFFF3F5F9));
            expect(SurfaceLevel.inset.colorOf(scheme), const Color(0xFFE9EDF4));
            expect(scheme.cardEdge.color, const Color(0xFFE6EAF1));
            expect(scheme.cardShadows, isNotEmpty);
          } else {
            expect(theme.colorScheme, scheme);
            expect(theme.cardTheme.color, isNot(theme.scaffoldBackgroundColor));
            expect(theme.canvasColor, scheme.surface);
            expect(scheme.cardEdge, BorderSide.none);
            expect(scheme.cardShadows, isEmpty);
          }
          expect(
            theme.colorScheme.chromeSurface,
            brightness == Brightness.light
                ? Colors.white
                : scheme.surfaceContainerLow,
          );
        }
      }
    },
  );
}
