import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:fl_clash/ui/ui.dart';

void main() {
  test(
    'light surfaces match the cool white preview while dark stays themed',
    () {
      for (final brightness in Brightness.values) {
        for (final seed in [
          const Color(0xFF2196F3),
          const Color(0xFF4CAF50),
          const Color(0xFFE91E63),
        ]) {
          final scheme = appSurfaceColors(
            seededColorScheme(seedColor: seed, brightness: brightness),
          );
          final theme = ThemeData(colorScheme: scheme);
          expect(theme.colorScheme, scheme);
          expect(
            theme.scaffoldBackgroundColor,
            SurfaceLevel.page.colorOf(scheme),
          );
          expect(
            SurfaceLevel.card.colorOf(scheme),
            SurfaceLevel.card.colorOf(scheme),
          );
          if (brightness == Brightness.light) {
            expect(theme.scaffoldBackgroundColor, Colors.white);
            expect(SurfaceLevel.card.colorOf(scheme), const Color(0xFFFCFCFE));
            expect(theme.colorScheme.surface, Colors.white);
            expect(scheme.surfaceContainerHigh, const Color(0xFFF3F5F9));
            expect(SurfaceLevel.inset.colorOf(scheme), const Color(0xFFE9EDF4));
            expect(scheme.cardEdge.color, const Color(0xFFE6EAF1));
          } else {
            expect(theme.colorScheme, scheme);
            expect(
              SurfaceLevel.card.colorOf(scheme),
              isNot(theme.scaffoldBackgroundColor),
            );
            expect(theme.colorScheme.surface, scheme.surface);
            expect(scheme.cardEdge, BorderSide.none);
          }
          expect(
            theme.colorScheme.appChromeSurface,
            brightness == Brightness.light
                ? Colors.white
                : scheme.surfaceContainerLow,
          );
        }
      }
    },
  );
}
