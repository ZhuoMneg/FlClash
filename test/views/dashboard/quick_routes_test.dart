import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/widgets/quick_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

class _RecordingAction extends ProxiesAction {
  final List<(String, String)> calls = [];

  @override
  void changeProxyDebounce(String groupName, String proxyName) {
    calls.add((groupName, proxyName));
    ref
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap(groupName, proxyName);
  }
}

Group _group(String name, String current, String next) => Group(
  type: GroupType.Selector,
  name: name,
  now: current,
  all: [
    Proxy(name: current, type: 'ss'),
    Proxy(name: next, type: 'ss'),
  ],
);

void main() {
  late ProviderContainer container;
  late _RecordingAction action;

  setUp(() {
    action = _RecordingAction();
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(
          () => TestProfiles([
            const Profile(id: 1, autoUpdateDuration: Duration.zero),
            const Profile(id: 2, autoUpdateDuration: Duration.zero),
          ]),
        ),
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        proxiesActionProvider.overrideWith(() => action),
      ],
    );
    globalState.container = container;
    container.listen(groupsProvider, (_, _) {});
    container.read(groupsProvider.notifier).value = [
      _group('DMIT protocol', 'VLESS Reality', 'Hysteria 2'),
      _group('🌐 Proxy', 'Proxy-A', 'Proxy-B'),
      _group('Emby', 'Emby-A', 'Emby-B'),
    ];
  });
  tearDown(() => container.dispose());

  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container.read(viewSizeProvider.notifier).value = const Size(1200, 1000);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: Center(
            child: DashboardDensityScope(
              density: DashboardDensity.compact,
              scale: 1,
              child: SizedBox(
                width: 380,
                height: 208,
                child: QuickRoutesCard(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
    'opens only the requested group and switches through the existing action',
    (tester) async {
      await pumpCard(tester);
      expect(find.text('VLESS Reality'), findsOneWidget);
      expect(find.text('Proxy-A'), findsOneWidget);
      expect(find.text('Emby-A'), findsOneWidget);
      await tester.tap(find.text('Proxy exit'));
      await tester.pumpAndSettle();
      expect(find.text('Proxy-B'), findsOneWidget);
      expect(find.text('Hysteria 2'), findsNothing);
      await tester.tap(find.text('Proxy-B'));
      await tester.pumpAndSettle();
      expect(action.calls, [('🌐 Proxy', 'Proxy-B')]);
      expect(find.text('Proxy-B'), findsOneWidget);
      expect(find.text('Emby-A'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets('binds an unmatched group and keeps the binding in settings', (
    tester,
  ) async {
    container.read(groupsProvider.notifier).value = [
      _group('Transport type', 'VLESS Reality', 'Hysteria 2'),
    ];
    await pumpCard(tester);
    await tester.tap(find.text('DMIT protocol'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proxy group').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport type'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      container
          .read(appSettingProvider)
          .profileQuickRoutes['1']!
          .singleWhere((route) => route.id == 'dmit')
          .groupName,
      'Transport type',
    );
    expect(find.text('VLESS Reality'), findsOneWidget);
    await tester.tap(find.text('DMIT protocol'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hysteria 2'));
    await tester.pumpAndSettle();
    expect(action.calls, [('Transport type', 'Hysteria 2')]);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets(
    'does not switch a group that disappeared while the picker was open',
    (tester) async {
      await pumpCard(tester);
      await tester.tap(find.text('Proxy exit'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<SelectionSheet<String>>(
        find.byType(SelectionSheet<String>),
      );
      container.read(groupsProvider.notifier).value = [];
      sheet.onSelected('Proxy-B');
      await tester.pump();
      expect(action.calls, isEmpty);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets('edits the binding of an already matched shortcut', (
    tester,
  ) async {
    container.read(groupsProvider.notifier).value = [
      ...container.read(groupsProvider),
      _group('Secondary', 'Other-A', 'Other-B'),
    ];
    await pumpCard(tester);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proxy exit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proxy group').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Secondary'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      container
          .read(appSettingProvider)
          .profileQuickRoutes['1']!
          .singleWhere((route) => route.id == 'proxy')
          .groupName,
      'Secondary',
    );
    Navigator.of(tester.element(find.text('Proxy exit').last)).pop();
    await tester.pumpAndSettle();
    expect(find.text('Other-A'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets(
    'favorite and recent choices are saved only for the active profile',
    (tester) async {
      await pumpCard(tester);
      await tester.tap(find.text('Proxy exit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add to favorites').last);
      await tester.pumpAndSettle();
      expect(
        container.read(appSettingProvider).quickRouteFavorites['1:🌐 Proxy'],
        ['Proxy-B'],
      );
      await tester.tap(find.text('Proxy-B'));
      await tester.pumpAndSettle();
      expect(
        container.read(appSettingProvider).quickRouteRecents['1:🌐 Proxy'],
        ['Proxy-B'],
      );
      expect(
        container.read(appSettingProvider).quickRouteFavorites['2:🌐 Proxy'],
        isNull,
      );
      await close(tester);
    },
  );

  testWidgets(
    'a picker opened for another profile cannot change its replacement',
    (tester) async {
      await pumpCard(tester);
      await tester.tap(find.text('Proxy exit'));
      await tester.pumpAndSettle();
      final picker = tester.widget<SelectionSheet<String>>(
        find.byType(SelectionSheet<String>),
      );
      container.read(currentProfileIdProvider.notifier).value = 2;
      picker.onSelected('Proxy-B');
      await tester.pump();
      expect(action.calls, isEmpty);
      expect(container.read(appSettingProvider).quickRouteRecents, isEmpty);
      await close(tester);
    },
  );
}
