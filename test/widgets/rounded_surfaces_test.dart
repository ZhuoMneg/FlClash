import 'package:fl_clash/manager/window_manager.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  test('light surface roles stay cool white across seeds and styles', () {
    for (final style in ColorStyle.values) {
      for (final seed in [
        const Color(0xFF2196F3),
        const Color(0xFF4CAF50),
        const Color(0xFFE91E63),
      ]) {
        final original = seededColorScheme(
          seedColor: seed,
          brightness: Brightness.light,
          style: style,
        );
        final scheme = appSurfaceColors(original);
        expect(scheme.surface, Colors.white);
        expect(scheme.surfaceDim, Colors.white);
        expect(scheme.surfaceContainerLowest, Colors.white);
        expect(scheme.surfaceContainerLow, Colors.white);
        expect(SurfaceLevel.page.colorOf(scheme), Colors.white);
        expect(SurfaceLevel.card.colorOf(scheme), Colors.white);
        expect(SurfaceLevel.block.colorOf(scheme), Colors.white);
        expect(scheme.surfaceContainerHigh, const Color(0xFFF3F8FF));
        expect(SurfaceLevel.inset.colorOf(scheme), const Color(0xFFE9F3FF));
        expect(scheme.appChromeSurface, Colors.white);
        expect(scheme.cardEdge, const BorderSide(color: Color(0xFFDEEBFA)));
        expect(scheme.primary, original.primary);
        expect(scheme.onSurface, original.onSurface);
      }
    }
  });

  test('dark schemes retain their original surface roles', () {
    for (final style in ColorStyle.values) {
      for (final seed in [
        const Color(0xFF2196F3),
        const Color(0xFF4CAF50),
        const Color(0xFFE91E63),
      ]) {
        final original = seededColorScheme(
          seedColor: seed,
          brightness: Brightness.dark,
          style: style,
        );
        final scheme = appSurfaceColors(original);
        expect(identical(scheme, original), isTrue);
        expect(scheme.appChromeSurface, original.chromeSurface);
        expect(scheme.cardEdge, BorderSide.none);
      }
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('window chrome in $brightness', (tester) async {
      final scheme = appSurfaceColors(
        seededColorScheme(
          seedColor: const Color(0xFF2196F3),
          brightness: brightness,
        ),
      );
      final theme = ThemeData(colorScheme: scheme);
      await tester.pumpWidget(
        TestApp(
          theme: theme,
          darkTheme: theme,
          themeMode: brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
          child: WindowHeaderBar(
            height: 40,
            onDragStart: () {},
            leading: const WindowHeaderBrand(),
          ),
        ),
      );
      final header = find.byType(WindowHeaderBar);
      final surface = tester.widget<Surface>(
        find.descendant(of: header, matching: find.byType(Surface)),
      );
      final background = tester.widget<ColoredBox>(
        find.descendant(of: header, matching: find.byType(ColoredBox)),
      );
      expect(background.color, scheme.appChromeSurface);
      expect(find.byType(WindowHeaderBrand), findsOneWidget);
      expect(find.text('FlClash'), findsOneWidget);
      if (brightness == Brightness.light) {
        expect(surface.shape, isNull);
      } else {
        expect(
          surface.shape,
          Border(bottom: Divider.createBorderSide(tester.element(header))),
        );
      }
    });

    testWidgets('dashboard and list surfaces in $brightness', (tester) async {
      final scheme = appSurfaceColors(
        seededColorScheme(
          seedColor: const Color(0xFF2196F3),
          brightness: brightness,
        ),
      );
      final theme = ThemeData(colorScheme: scheme);
      const foregroundSide = BorderSide(color: Color(0xFFFF0000), width: 2);
      await tester.pumpWidget(
        TestApp(
          theme: theme,
          darkTheme: theme,
          themeMode: brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
          child: const DashboardDensityScope(
            density: DashboardDensity.standard,
            scale: 1,
            child: Column(
              children: [
                DashboardCard(
                  key: ValueKey('default-card'),
                  child: SizedBox(
                    key: ValueKey('dashboard-content'),
                    width: 200,
                    height: 50,
                  ),
                ),
                DashboardCard(
                  key: ValueKey('custom-card'),
                  side: foregroundSide,
                  child: SizedBox(width: 200, height: 50),
                ),
                DecorationListItem(title: Text('list row')),
              ],
            ),
          ),
        ),
      );

      final card = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('default-card')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is ShapeDecoration,
          ),
        ),
      );
      final decoration = card.decoration! as ShapeDecoration;
      final cardRect = tester.getRect(find.byWidget(card));
      final contentRect = tester.getRect(
        find.byKey(const ValueKey('dashboard-content')),
      );
      expect(contentRect.left - cardRect.left, 22);
      expect(contentRect.top - cardRect.top, 20);
      expect(cardRect.height, 90);
      final shape = AppShape.all(
        dashboardCardRadius(DashboardDensity.standard),
      );
      expect(decoration.color, SurfaceLevel.card.colorOf(scheme));
      expect(decoration.shape, shape);
      expect(
        card.foregroundDecoration,
        scheme.cardEdge == BorderSide.none
            ? null
            : ShapeDecoration(shape: shape.copyWith(side: scheme.cardEdge)),
      );
      final customCard = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('custom-card')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is ShapeDecoration,
          ),
        ),
      );
      expect(
        (customCard.foregroundDecoration! as ShapeDecoration).shape,
        shape.copyWith(side: foregroundSide),
      );
      final listCard = tester.widget<Card>(
        find.descendant(
          of: find.byType(DecorationListItem),
          matching: find.byType(Card),
        ),
      );
      final pressSurface = tester.widget<PressSurface>(
        find
            .descendant(
              of: find.byWidget(listCard),
              matching: find.byType(PressSurface),
            )
            .first,
      );
      expect(pressSurface.fill, SurfaceLevel.card.colorOf(scheme));
      expect(pressSurface.shape, AppShape.of(listItemRadiusOf(null)));
    });
  }
}
