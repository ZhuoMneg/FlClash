import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/config.dart' show defaultWindowSize;
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/dashboard.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/widgets/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

void main() {
  test('the window picks the density', () {
    DashboardDensity of(double width, double height) =>
        DashboardDensity.of(Size(width, height));

    expect(of(1220, 900), DashboardDensity.standard);
    expect(of(1220, 824), DashboardDensity.standard);
    expect(of(1220, 823), DashboardDensity.compact);
    expect(of(1220, 500), DashboardDensity.compact);
    expect(of(1039, 900), DashboardDensity.compact);
    expect(of(860, 900), DashboardDensity.compact);
    expect(of(859, 900), DashboardDensity.standard);
    expect(of(640, 900), DashboardDensity.standard);
    expect(of(640, 823), DashboardDensity.compact);
    expect(of(639, 900), DashboardDensity.mobile);
    expect(dashboardColumnsOf(860), 4);
    expect(dashboardColumnsOf(859), 2);
  });

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    globalState.container = container;
    container.listen(groupsProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  Future<void> pumpDashboard(
    WidgetTester tester,
    Size size, {
    SupportPlatform platform = SupportPlatform.MacOS,
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    container.read(viewSizeProvider.notifier).value = size;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          theme: ThemeData(brightness: brightness),
          child: DashboardView(platform: platform),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  }

  Rect rectOf(WidgetTester tester, Type type) =>
      tester.getRect(find.byType(type).first);

  double scrollExtentOf(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .maxScrollExtent;

  testWidgets('the desktop keeps the fixed cards in two rows', (tester) async {
    await pumpDashboard(tester, const Size(1220, 824));
    final current = rectOf(tester, CurrentOutboundCard);
    final traffic = rectOf(tester, TrafficOverviewCard);
    final mode = rectOf(tester, OutboundModeBar);
    final proxy = tester.getRect(find.byType(NetworkTakeoverTile).first);
    final tun = tester.getRect(find.byType(NetworkTakeoverTile).last);
    expect(current.height, 208);
    expect(current.width, closeTo(traffic.width * 2 + 16, 0.01));
    expect(traffic.left, closeTo(current.right + 16, 0.01));
    expect(proxy.left, closeTo(traffic.right + 16, 0.01));
    expect(proxy.top, current.top);
    expect(tun.bottom, current.bottom);
    expect(mode.top, current.bottom + 16);
    expect(mode.height, 64);
    expect(mode.width, closeTo(current.width, 0.01));
    expect(find.byType(NetworkTunnelTile), findsNothing);
    expect(find.byType(IntranetIpCard), findsNothing);
    expect(find.byType(MemoryInfo), findsNothing);
    expect(find.byType(SpeedCard), findsNothing);
    expect(find.byType(ProfilesCard), findsNothing);
    expect(find.byType(ServiceStatusCard), findsNothing);
    expect(find.byType(ConnectionsTableCard), findsNothing);
    expect(find.byType(ProxyGroupsCard), findsNothing);
    expect(find.byType(ConnectionStatsCard), findsNothing);
    expect(find.byType(ProxyGroupsSummaryCard), findsNothing);
    expect(find.byType(OutboundModeCard), findsNothing);
    expect(find.byType(LiveStatusButton), findsOneWidget);
    expect(scrollExtentOf(tester), 0);
    expect(tester.takeException(), isNull);
    await teardown(tester);
  });

  testWidgets('the default window opens on four full columns beside the '
      'expanded sidebar and a title bar', (tester) async {
    const sidebar = 220.0;
    const titleBar = 32.0;
    await pumpDashboard(
      tester,
      Size(
        defaultWindowSize.width - sidebar,
        defaultWindowSize.height - titleBar,
      ),
    );

    expect(rectOf(tester, CurrentOutboundCard).height, 208);
    expect(find.byType(TrafficOverviewCard), findsOneWidget);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('a short window keeps the layout with compact rows', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(1220, 720));

    expect(rectOf(tester, CurrentOutboundCard).height, 176);
    expect(rectOf(tester, OutboundModeBar).height, 56);
    expect(scrollExtentOf(tester), 0);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('a very short window can scroll to the tunnel', (tester) async {
    await pumpDashboard(
      tester,
      const Size(800, 300),
      platform: SupportPlatform.Windows,
    );
    expect(scrollExtentOf(tester), greaterThan(0));
    await tester.scrollUntilVisible(
      find.byType(NetworkTunnelTile),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(rectOf(tester, NetworkTunnelTile).bottom, lessThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
    await teardown(tester);
  });

  testWidgets('a wide window centres columns that stop growing', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(2560, 1440));

    final current = rectOf(tester, CurrentOutboundCard);
    final tun = tester.getRect(find.byType(NetworkTakeoverTile).last);
    expect(rectOf(tester, TrafficOverviewCard).width, 440);
    expect(current.left - 16, closeTo(2560 - 24 - tun.right, 0.01));
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('a resize lays the cards out for the new width in its first '
      'frame, before the view size catches up', (tester) async {
    await pumpDashboard(tester, const Size(1440, 900));

    tester.view.physicalSize = const Size(600, 800);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(OutboundModeCard), findsOneWidget);
    expect(find.byType(OutboundModeBar), findsNothing);

    tester.view.physicalSize = const Size(800, 900);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(rectOf(tester, OutboundModeBar).width, 800 - 16 - 24);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(TrafficOverviewCard), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('larger text grows the box of every line', (tester) async {
    container.listen(localIpProvider, (_, _) {});
    container.read(localIpProvider.notifier).value = '192.168.100.200';
    List<String> clipped() => [
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.byType(RichText),
      ))
        if (paragraph.getMaxIntrinsicHeight(paragraph.size.width) >
            paragraph.size.height + 0.5)
          paragraph.text.toPlainText(),
    ];
    for (final (size, platform) in const [
      (Size(1440, 900), SupportPlatform.MacOS),
      (Size(1000, 1000), SupportPlatform.MacOS),
      (Size(412, 915), SupportPlatform.Android),
    ]) {
      for (final textScale in const [1.2, 1.4]) {
        await pumpDashboard(
          tester,
          size,
          platform: platform,
          textScale: textScale,
        );
        expect(clipped(), isEmpty, reason: '$size x$textScale');
        expect(tester.takeException(), isNull);
      }
    }

    await teardown(tester);
  });

  testWidgets('a mid-width window stacks the cards in two columns', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(800, 900));
    final gap = cardSpacingOf(
      tester.element(find.byType(CurrentOutboundCard)),
      ViewMode.laptop,
    );
    final current = rectOf(tester, CurrentOutboundCard);
    final traffic = rectOf(tester, TrafficOverviewCard);
    final mode = rectOf(tester, OutboundModeBar);
    final proxy = tester.getRect(find.byType(NetworkTakeoverTile).first);
    final tun = tester.getRect(find.byType(NetworkTakeoverTile).last);
    expect(current.width, 800 - 16 - 24);
    expect(current.width, closeTo(traffic.width * 2 + gap, 0.01));
    expect(traffic.top, current.bottom + gap);
    expect(proxy.left, closeTo(traffic.right + gap, 0.01));
    expect(proxy.top, traffic.top);
    expect(proxy.height, 64);
    expect(tun.top, proxy.bottom + gap);
    expect(tun.bottom, traffic.bottom);
    expect(mode.top, traffic.bottom + gap);
    expect(mode.width, current.width);
    expect(find.byType(NetworkTunnelTile), findsNothing);
    expect(find.byType(ProfilesCard), findsNothing);
    expect(find.byType(ServiceStatusCard), findsNothing);
    expect(find.byType(ConnectionsTableCard), findsNothing);
    expect(find.byType(ConnectionStatsCard), findsNothing);
    expect(find.byType(ProxyGroupsSummaryCard), findsNothing);
    expect(find.byType(OutboundModeCard), findsNothing);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(tester.takeException(), isNull);
    await teardown(tester);
  });

  testWidgets('Windows places the tunnel after the mode in both grids', (
    tester,
  ) async {
    for (final size in const [Size(800, 900), Size(1220, 824)]) {
      await pumpDashboard(tester, size, platform: SupportPlatform.Windows);
      final current = rectOf(tester, CurrentOutboundCard);
      final traffic = rectOf(tester, TrafficOverviewCard);
      final mode = rectOf(tester, OutboundModeBar);
      final tunnel = rectOf(tester, NetworkTunnelTile);
      final gap = cardSpacingOf(
        tester.element(find.byType(CurrentOutboundCard)),
        container.read(viewModeProvider),
      );
      if (size.width < 860) {
        expect(tunnel.top, mode.bottom + gap);
        expect(tunnel.width, current.width);
      } else {
        expect(tunnel.left, mode.right + gap);
        expect(tunnel.top, mode.top);
        expect(tunnel.width, mode.width);
        expect(traffic.top, current.top);
      }
      expect(tunnel.height, 64);
      expect(tester.takeException(), isNull);
    }
    await teardown(tester);
  });

  testWidgets('Windows grids fit light and dark themes at larger text scales', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final size in const [
        Size(500, 700),
        Size(620, 900),
        Size(800, 900),
        Size(860, 900),
        Size(1040, 900),
        Size(1440, 900),
      ]) {
        for (final scale in const [1.0, 1.2, 1.4]) {
          await pumpDashboard(
            tester,
            size,
            platform: SupportPlatform.Windows,
            textScale: scale,
            brightness: brightness,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$brightness $size x$scale',
          );
        }
      }
    }
    await teardown(tester);
  });

  testWidgets('larger text grows the rows and narrows the grid', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(1400, 1000), textScale: 1.2);
    expect(
      rectOf(tester, CurrentOutboundCard).height,
      closeTo(208 * 1.2, 0.01),
    );
    expect(tester.takeException(), isNull);

    await pumpDashboard(tester, const Size(1000, 1000), textScale: 1.2);
    final current = rectOf(tester, CurrentOutboundCard);
    expect(current.width, 1000 - 16 - 24);
    expect(current.height, closeTo(208 * 1.2, 0.01));
    expect(tester.takeException(), isNull);

    await pumpDashboard(tester, const Size(760, 1000), textScale: 1.2);
    expect(find.byType(ConnectionsTableCard), findsNothing);
    expect(find.byType(OutboundModeBar), findsNothing);
    expect(rectOf(tester, CurrentOutboundCard).width, 560);

    await teardown(tester);
  });

  testWidgets('a narrow Windows window keeps the fixed cards', (tester) async {
    await pumpDashboard(
      tester,
      const Size(620, 500),
      platform: SupportPlatform.Windows,
    );

    expect(find.byTooltip('Edit dashboard'), findsNothing);
    expect(find.byType(OutboundModeBar), findsOneWidget);
    expect(find.byType(NetworkTakeoverTile), findsNWidgets(2));
    expect(find.byType(ProfilesCard), findsNothing);
    expect(find.byType(ServiceStatusCard), findsNothing);
    expect(find.byType(ConnectionStatsCard), findsNothing);
    expect(find.byType(ProxyGroupsSummaryCard), findsNothing);
    await tester.scrollUntilVisible(
      find.byType(NetworkTunnelTile),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(rectOf(tester, NetworkTunnelTile).bottom, lessThanOrEqualTo(500));
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('a narrow desktop window shows the phone cards in a centred '
      'column, takeover in place of the VPN', (tester) async {
    await pumpDashboard(tester, const Size(620, 700));

    final card = rectOf(tester, CurrentOutboundCard);
    expect(card.width, 560);
    expect(card.center.dx, closeTo(310, 0.01));
    expect(find.byType(NetworkTakeoverCard), findsOneWidget);
    expect(find.byType(VpnCard), findsNothing);
    expect(find.byType(OutboundModeCard), findsOneWidget);
    expect(find.byType(OutboundModeBar), findsNothing);

    await teardown(tester);
  });

  testWidgets('a phone shows the saved cards edge to edge', (tester) async {
    await pumpDashboard(
      tester,
      const Size(400, 900),
      platform: SupportPlatform.Android,
    );

    final card = rectOf(tester, CurrentOutboundCard);
    expect(card.left, 16);
    expect(card.right, 400 - 16);
    expect(find.byType(VpnCard), findsOneWidget);
    expect(find.byType(NetworkTakeoverCard), findsNothing);

    await teardown(tester);
  });

  testWidgets('a tablet or a landscape phone gets the same grid, the VPN '
      'switch in place of the takeover', (tester) async {
    for (final size in const [Size(1280, 800), Size(915, 412)]) {
      await pumpDashboard(tester, size, platform: SupportPlatform.Android);

      final mode = rectOf(tester, OutboundModeBar);
      final vpn = rectOf(tester, VpnTile);
      expect(vpn.width * 2 + 16, closeTo(mode.width, 0.01));
      expect(vpn.height, rectOf(tester, CurrentOutboundCard).height);
      expect(find.byType(NetworkTakeoverTile), findsNothing);
      expect(find.byType(CurrentOutboundCard), findsOneWidget);
      expect(find.byType(NetworkSpeedCard), findsNothing);
      expect(tester.takeException(), isNull);
    }

    await teardown(tester);
  });
}
