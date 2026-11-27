import 'dart:async';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/network_tunnel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';

class _Core extends Mock implements CoreHandlerInterface {}

void main() {
  Future<ProviderContainer> pumpPage(
    WidgetTester tester,
    NetworkTunnelSettings settings, {
    Future<Map<String, dynamic>> Function()? poll,
  }) async {
    final core = _Core();
    when(() => core.getNetworkTunnelStatus()).thenAnswer(
      (_) async =>
          poll == null ? {'running': true, 'received': 0} : await poll(),
    );
    when(() => core.refreshNetworkTunnel()).thenThrow(StateError('offline'));
    final container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        networkSettingProvider.overrideWithBuild(
          (_, _) => NetworkProps(networkTunnel: settings),
        ),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1200, 1000);
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(locale: Locale('en'), child: NetworkTunnelView()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('unconfigured page offers import without enabling a tunnel', (
    tester,
  ) async {
    await pumpPage(tester, const NetworkTunnelSettings());
    expect(find.text('Configuration required'), findsOneWidget);
    expect(find.text('Import tunnel configuration'), findsOneWidget);
    expect(find.text('Disable both'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'independent switches, one-click disable and refresh failure are safe',
    (tester) async {
      const fallbacks = [
        NetworkTunnelDirectory(host: '198.51.100.20', pin: 'test-pin'),
      ];
      final container = await pumpPage(
        tester,
        const NetworkTunnelSettings(
          host: '192.0.2.10',
          token: 'test-token',
          privateKey: 'test-key',
          profileId: 1,
          fallbacks: fallbacks,
        ),
      );
      await tester.tap(find.text('Refresh endpoint'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('WireGuard'));
      await tester.pumpAndSettle();
      var settings = container.read(networkSettingProvider).networkTunnel;
      expect(settings.enabled, isFalse);
      expect(settings.extension, isTrue);
      expect(
        find.text('WireGuard is off; the extension cannot connect'),
        findsOneWidget,
      );
      await tester.tap(find.text('WireGuard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disable both'));
      await tester.pumpAndSettle();
      settings = container.read(networkSettingProvider).networkTunnel;
      expect(settings.enabled || settings.extension, isFalse);
      expect(settings.fallbacks, fallbacks);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final change in ['core', 'settings', 'profile']) {
    testWidgets('$change changes discard cached and in-flight tunnel status', (
      tester,
    ) async {
      const oldEndpoint = '119.39.89.123:15140';
      const newEndpoint = '119.39.89.124:15141';
      const settings = NetworkTunnelSettings(
        host: '179.253.249.97',
        token: 'test-token',
        privateKey: 'test-key',
        profileId: 1,
      );
      final pending = <Completer<Map<String, dynamic>>>[];
      var first = true;
      final container = await pumpPage(
        tester,
        settings,
        poll: () {
          if (first) {
            first = false;
            return Future.value({'running': true, 'home': oldEndpoint});
          }
          final reply = Completer<Map<String, dynamic>>();
          pending.add(reply);
          return reply.future;
        },
      );
      expect(find.text(oldEndpoint), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(pending, hasLength(1));
      switch (change) {
        case 'core':
          container.read(coreStatusProvider.notifier).value =
              CoreStatus.disconnected;
          container.read(coreStatusProvider.notifier).value =
              CoreStatus.connected;
        case 'settings':
          container.read(networkSettingProvider.notifier).value = NetworkProps(
            networkTunnel: settings.copyWith(port: 27035),
          );
        case 'profile':
          container.read(currentProfileIdProvider.notifier).value = 2;
          container.read(currentProfileIdProvider.notifier).value = 1;
      }
      await tester.pump();
      expect(find.text(oldEndpoint), findsNothing);
      expect(pending.length, greaterThan(1));
      pending.last.complete({'running': true, 'home': newEndpoint});
      await tester.pumpAndSettle();
      expect(find.text(newEndpoint), findsOneWidget);
      for (final reply in pending.take(pending.length - 1)) {
        if (change == 'core') {
          reply.completeError(StateError('old core reply'));
        } else {
          reply.complete({'running': true, 'home': oldEndpoint});
        }
      }
      await tester.pump();
      expect(find.text(oldEndpoint), findsNothing);
      expect(find.text(newEndpoint), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
