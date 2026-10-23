import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/dashboard.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

void main() {
  test('density follows available size', () {
    expect(
      DashboardDensity.of(const Size(1220, 900)),
      DashboardDensity.standard,
    );
    expect(
      DashboardDensity.of(const Size(1220, 500)),
      DashboardDensity.compact,
    );
    expect(DashboardDensity.of(const Size(400, 900)), DashboardDensity.mobile);
    expect(dashboardColumnsOf(860), 4);
    expect(dashboardColumnsOf(859), 2);
  });

  for (final size in const [
    Size(400, 900),
    Size(640, 900),
    Size(800, 900),
    Size(1000, 900),
    Size(1220, 824),
    Size(1440, 900),
    Size(1440, 660),
    Size(2000, 1440),
  ]) {
    for (final scale in [1.0, 1.4]) {
      if (size.width == 400 && scale > 1) continue;
      testWidgets('dashboard reflows without removed feeds at $size x$scale', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [profilesProvider.overrideWith(TestProfiles.new)],
        );
        globalState.container = container;
        container.listen(groupsProvider, (_, _) {});
        container.read(groupsProvider.notifier).value = [
          for (var index = 0; index < 4; index++)
            Group(
              name: 'Group $index',
              type: GroupType.Selector,
              hidden: false,
              all: [Proxy(name: 'Node $index', type: 'ss')],
            ),
        ];
        container.read(viewSizeProvider.notifier).value = size;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(
              child: DashboardView(platform: SupportPlatform.Windows),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(ConnectionsTableCard), findsNothing);
        expect(find.byType(ConnectionStatsCard), findsNothing);
        expect(find.text('Route shortcuts'), findsNothing);
        expect(find.byType(ProfilesCard), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (scale == 1 && size.width == 1440 && size.height == 900) {
          Rect rect(Type type) => tester.getRect(find.byType(type).first);
          final intranet = rect(IntranetIpCard);
          final profile = rect(ProfilesCard);
          final memory = rect(MemoryInfo);
          expect(profile.left, closeTo(intranet.right + 16, 0.01));
          expect(memory.left, closeTo(profile.right + 16, 0.01));
          expect(memory.top, profile.top);
          expect(profile.width, closeTo(intranet.width * 2 + 16, 0.01));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
        container.dispose();
      });
    }
  }
}
