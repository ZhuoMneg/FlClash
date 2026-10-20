import 'package:fl_clash/ui/color.dart';
import 'package:fl_clash/ui/surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('white pages keep neutral cards distinct for every accent', () {
    for (final seed in [Colors.blue, Colors.green, Colors.pink]) {
      final theme = ThemeData(
        colorScheme: seededColorScheme(
          seedColor: seed,
          brightness: Brightness.light,
        ),
      ).withAppSurfaces;

      expect(theme.scaffoldBackgroundColor, Colors.white);
      expect(theme.cardTheme.color, const Color(0xFFF5F6F8));
      expect(theme.cardTheme.color, isNot(theme.scaffoldBackgroundColor));
      final card = SurfaceLevel.card.colorOf(theme.colorScheme);
      final block = SurfaceLevel.block.colorOf(theme.colorScheme);
      final inset = SurfaceLevel.inset.colorOf(theme.colorScheme);
      expect(card.computeLuminance(), greaterThan(block.computeLuminance()));
      expect(block.computeLuminance(), greaterThan(inset.computeLuminance()));
      expect(theme.colorScheme.chromeSurface, Colors.white);
      expect(theme.colorScheme.primary, isNot(Colors.white));
      expect(theme.colorScheme.onSurface.computeLuminance(), lessThan(0.1));
    }
  });

  test('dark surfaces stay dark', () {
    final scheme = seededColorScheme(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    );
    final theme = ThemeData(colorScheme: scheme).withAppSurfaces;

    expect(theme.colorScheme, scheme);
    expect(theme.scaffoldBackgroundColor, scheme.surface);
  });
}
