import 'dart:async';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:fl_clash/views/dashboard/widgets/network_tunnel.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/host_scaffold.dart';
import '../../helpers/test_app.dart';

class _Core extends Mock implements CoreHandlerInterface {}

const _configured = NetworkTunnelSettings(
  host: 'example.com',
  port: 1234,
  token: 'token',
  privateKey: 'key',
  profileId: 1,
);

void main() {
  late _Core core;
  late ProviderContainer container;

  Future<void> mount(
    WidgetTester tester, {
    NetworkTunnelSettings settings = _configured,
    CoreStatus status = CoreStatus.connected,
    int profile = 1,
    bool tickerEnabled = true,
  }) async {
    core = _Core();
    when(() => core.getNetworkTunnelStatus()).thenAnswer((_) async => {});
    container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile),
        networkSettingProvider.overrideWithBuild(
          (_, _) => NetworkProps(networkTunnel: settings),
        ),
        coreStatusProvider.overrideWithBuild((_, _) => status),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    globalState.container = container;
    container.listen(currentPageLabelProvider, (_, _) {});
    container.listen(networkSettingProvider, (_, _) {});
    container.listen(currentProfileIdProvider, (_, _) {});
    container.read(viewSizeProvider.notifier).value = const Size(400, 800);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: const Locale('en'),
          child: HostScaffold(
            body: TickerMode(
              enabled: tickerEnabled,
              child: const NetworkTunnelTile(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('unconfigured switch opens settings without changing them', (
    tester,
  ) async {
    const settings = NetworkTunnelSettings();
    await mount(tester, settings: settings);
    expect(
      tester.widget<DashboardSwitch>(find.byType(DashboardSwitch)).value,
      isFalse,
    );
    await tester.tap(find.byType(DashboardSwitch));
    await tester.pump();
    expect(container.read(currentPageLabelProvider), PageLabel.networkTunnel);
    expect(container.read(networkSettingProvider).networkTunnel, settings);
    verifyNever(() => core.getNetworkTunnelStatus());
  });

  testWidgets('configured switch changes only enabled and does not navigate', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byType(DashboardSwitch));
    await tester.pump();
    expect(
      container.read(networkSettingProvider).networkTunnel,
      _configured.copyWith(enabled: false),
    );
    expect(container.read(currentPageLabelProvider), PageLabel.dashboard);
    await tester.tap(find.byType(DashboardSwitch));
    await tester.pump();
    expect(container.read(networkSettingProvider).networkTunnel, _configured);
    expect(container.read(currentPageLabelProvider), PageLabel.dashboard);
  });

  testWidgets('unconfigured card blank space opens settings', (tester) async {
    const settings = NetworkTunnelSettings();
    await mount(tester, settings: settings);
    await tester.tapAt(
      tester.getTopLeft(find.byType(NetworkTunnelTile)) + const Offset(80, 10),
    );
    await tester.pump();
    expect(container.read(currentPageLabelProvider), PageLabel.networkTunnel);
    expect(container.read(networkSettingProvider).networkTunnel, settings);
  });

  testWidgets('tapping the card opens settings without changing enabled', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Network Tunnel'));
    await tester.pump();
    expect(container.read(currentPageLabelProvider), PageLabel.networkTunnel);
    expect(container.read(networkSettingProvider).networkTunnel, _configured);
  });

  for (final condition in ['disabled', 'disconnected', 'profile mismatch']) {
    testWidgets('$condition does not poll', (tester) async {
      await mount(
        tester,
        settings: condition == 'disabled'
            ? _configured.copyWith(enabled: false)
            : _configured,
        status: condition == 'disconnected'
            ? CoreStatus.disconnected
            : CoreStatus.connected,
        profile: condition == 'profile mismatch' ? 2 : 1,
      );
      await tester.pump(const Duration(seconds: 9));
      verifyNever(() => core.getNetworkTunnelStatus());
    });
  }

  testWidgets('active tunnel displays live endpoint and receiving status', (
    tester,
  ) async {
    await mount(tester);
    when(() => core.getNetworkTunnelStatus()).thenAnswer(
      (_) async => {
        'running': true,
        'received': 2,
        'lastReply': DateTime.now().millisecondsSinceEpoch / 1000,
        'home': 'endpoint:1234',
      },
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.textContaining('endpoint:1234'), findsOneWidget);
    expect(
      find.textContaining('Encrypted replies received recently'),
      findsOneWidget,
    );
  });

  for (final change in ['core', 'settings', 'profile']) {
    testWidgets(
      '$change invalidates an in-flight response without concurrent polls',
      (tester) async {
        await mount(tester);
        final reply = Completer<Map<String, dynamic>>();
        when(
          () => core.getNetworkTunnelStatus(),
        ).thenAnswer((_) => reply.future);
        await tester.pump(const Duration(seconds: 3));
        clearInteractions(core);
        await tester.pump(const Duration(seconds: 9));
        verifyNever(() => core.getNetworkTunnelStatus());
        switch (change) {
          case 'core':
            container.read(coreStatusProvider.notifier).value =
                CoreStatus.disconnected;
            container.read(coreStatusProvider.notifier).value =
                CoreStatus.connected;
          case 'settings':
            container.read(networkSettingProvider.notifier).value =
                NetworkProps(networkTunnel: _configured.copyWith(port: 5678));
          case 'profile':
            container.read(currentProfileIdProvider.notifier).value = 2;
            container.read(currentProfileIdProvider.notifier).value = 1;
        }
        await tester.pump();
        verifyNever(() => core.getNetworkTunnelStatus());
        reply.complete({'home': 'stale:1234'});
        await tester.pump();
        expect(find.textContaining('stale:1234'), findsNothing);
        when(
          () => core.getNetworkTunnelStatus(),
        ).thenAnswer((_) async => {'home': 'fresh:1234'});
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        expect(find.textContaining('fresh:1234'), findsOneWidget);
      },
    );
  }

  testWidgets('poll errors recover and completion after disposal is safe', (
    tester,
  ) async {
    await mount(tester);
    when(() => core.getNetworkTunnelStatus()).thenThrow(StateError('offline'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(tester.takeException(), isNull);
    when(
      () => core.getNetworkTunnelStatus(),
    ).thenAnswer((_) async => {'home': 'recovered:1234'});
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.textContaining('recovered:1234'), findsOneWidget);
    final reply = Completer<Map<String, dynamic>>();
    when(() => core.getNetworkTunnelStatus()).thenAnswer((_) => reply.future);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    reply.complete({'home': 'late:1234'});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ticker mode pauses polling', (tester) async {
    await mount(tester, tickerEnabled: false);
    await tester.pump(const Duration(seconds: 9));
    verifyNever(() => core.getNetworkTunnelStatus());
  });

  testWidgets('background pauses polling and resume refreshes it', (
    tester,
  ) async {
    await mount(tester);
    clearInteractions(core);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 9));
    verifyNever(() => core.getNetworkTunnelStatus());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    verify(() => core.getNetworkTunnelStatus()).called(1);
  });
}
