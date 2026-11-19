import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/connection/network_activity.dart';
import 'package:fl_clash/views/connection/requests.dart';
import 'package:fl_clash/views/dns_queries.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/core_connections.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _Core extends Mock implements CoreHandlerInterface {}

void main() {
  for (final width in [400.0, 1400.0]) {
    testWidgets(
      'activity tabs preserve search and stop hidden polling at $width',
      (tester) async {
        final core = _Core();
        whenConnections<RankedTrackerInfos>(core, () async => const []);
        final container = ProviderContainer(
          overrides: [
            profilesProvider.overrideWith(TestProfiles.new),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          ],
        );
        globalState.container = container;
        container.read(coreStatusProvider.notifier).value =
            CoreStatus.connected;
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        container.read(viewSizeProvider.notifier).value = Size(width, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(child: NetworkActivityView()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Network activity'), findsOneWidget);
        expect(find.byType(RequestsView), findsOneWidget);
        expect(container.read(appSettingProvider).networkActivityTab, 1);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).titleMenuItems,
          isEmpty,
        );
        verifyNever(() => core.getConnectionsWith<RankedTrackerInfos>(any()));
        await tester.tap(find.byKey(const ValueKey('network-activity-tab-0')));
        await tester.pumpAndSettle();
        final liveScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(liveScaffold.titleMenuItems, isEmpty);
        expect(
          liveScaffold.iconActions.map((action) => action.glyph),
          contains(AppGlyphs.clearAll),
        );
        expect(container.read(appSettingProvider).networkActivityTab, 0);
        await tester.pump(const Duration(seconds: 1));
        verify(() => core.getConnectionsWith<RankedTrackerInfos>(any()));
        await tester.tap(find.byKey(const ValueKey('network-activity-tab-1')));
        await tester.pumpAndSettle();
        expect(find.byType(RequestsView), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'example.test');
        await tester.pumpAndSettle();
        clearInteractions(core);
        await tester.pump(const Duration(seconds: 3));
        verifyNever(() => core.getConnectionsWith<RankedTrackerInfos>(any()));
        await tester.tap(find.byKey(const ValueKey('network-activity-tab-2')));
        await tester.pumpAndSettle();
        expect(find.byType(DnsQueriesView), findsOneWidget);
        expect(container.read(appSettingProvider).networkActivityTab, 2);
        await tester.tap(find.byKey(const ValueKey('network-activity-tab-1')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'example.test',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
        container.dispose();
      },
    );
  }
}
