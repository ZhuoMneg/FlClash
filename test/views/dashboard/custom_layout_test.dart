import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/dashboard.dart';
import 'package:fl_clash/views/dashboard/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

void main() {
  late ProviderContainer container;
  setUp(() {
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    globalState.container = container;
    container.listen(appSettingProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  Future<void> pumpDashboard(
    WidgetTester tester,
    Size size,
    List<DashboardWidget> cards, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    container.read(viewSizeProvider.notifier).value = size;
    container
        .read(appSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            desktopDashboardCustomized: true,
            dashboardWidgets: cards,
          ),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: DashboardView(platform: SupportPlatform.Windows),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> closeDashboard(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets(
    'custom desktop shows only the saved cards and follows their order immediately',
    (tester) async {
      await pumpDashboard(tester, const Size(1220, 900), [
        DashboardWidget.memoryInfo,
        DashboardWidget.intranetIp,
        DashboardWidget.currentOutbound,
      ]);
      expect(find.byType(QuickRoutesCard), findsNothing);
      expect(find.byType(ProfilesCard), findsNothing);
      Rect rect(DashboardWidget card) =>
          tester.getRect(find.byKey(ValueKey('desktop-${card.name}')));
      expect(
        rect(DashboardWidget.memoryInfo).left,
        lessThan(rect(DashboardWidget.intranetIp).left),
      );
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              dashboardWidgets: [
                DashboardWidget.intranetIp,
                DashboardWidget.memoryInfo,
                DashboardWidget.currentOutbound,
              ],
            ),
          );
      await tester.pump();
      expect(
        rect(DashboardWidget.intranetIp).left,
        lessThan(rect(DashboardWidget.memoryInfo).left),
      );
      expect(tester.takeException(), isNull);
      await closeDashboard(tester);
    },
  );

  for (final card in DashboardWidget.values.where(
    (card) => card.platforms.contains(SupportPlatform.Windows),
  )) {
    testWidgets(
      'custom desktop ${card.name} fits at two and four columns with larger text',
      (tester) async {
        for (final (size, scale) in const [
          (Size(1220, 900), 1.0),
          (Size(800, 1000), 1.0),
          (Size(1220, 1000), 1.4),
        ]) {
          await pumpDashboard(tester, size, [card], textScale: scale);
          expect(
            tester.takeException(),
            isNull,
            reason: '${card.name}: $size x$scale',
          );
          await closeDashboard(tester);
        }
      },
    );
  }

  testWidgets(
    'every selectable desktop card fits a custom layout at two and four columns with larger text',
    (tester) async {
      final cards = DashboardWidget.values
          .where((card) => card.platforms.contains(SupportPlatform.Windows))
          .toList();
      for (final (size, scale) in const [
        (Size(1220, 900), 1.0),
        (Size(800, 1000), 1.0),
        (Size(1220, 1000), 1.4),
      ]) {
        await pumpDashboard(tester, size, cards, textScale: scale);
        for (final card in cards) {
          final rect = tester.getRect(
            find.byKey(ValueKey('desktop-${card.name}')),
          );
          expect(rect.left, greaterThanOrEqualTo(0), reason: card.name);
          expect(rect.right, lessThanOrEqualTo(size.width), reason: card.name);
        }
        expect(tester.takeException(), isNull, reason: '$size x$scale');
        await closeDashboard(tester);
      }
    },
  );
}
