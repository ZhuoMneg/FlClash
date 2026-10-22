import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/navigation.dart';
import 'package:fl_clash/views/settings/navigation_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  late ProviderContainer container;
  NavigationPort? previousNavigation;

  setUp(() {
    previousNavigation = navigationPort;
    navigationPort = navigation;
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        currentGroupsStateProvider.overrideWithValue(
          const GroupsState(value: []),
        ),
      ],
    );
    globalState.container = container;
    container.listen(appSettingProvider, (_, _) {});
    container.listen(currentNavigationItemsStateProvider, (_, _) {});
    container.read(viewSizeProvider.notifier).value = const Size(1200, 1000);
  });
  tearDown(() {
    container.dispose();
    navigationPort = previousNavigation;
  });

  List<PageLabel> shownItems() => container
      .read(currentNavigationItemsStateProvider)
      .value
      .map((item) => item.label)
      .toList();

  test(
    'pinned tools become valid desktop destinations and unpinning falls back safely',
    () {
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              pinnedTools: ['connections', 'dns', 'logs', 'future-tool'],
            ),
          );
      expect(
        shownItems(),
        containsAll([PageLabel.connections, PageLabel.dns, PageLabel.logs]),
      );
      container.read(currentPageLabelProvider.notifier).toPage(PageLabel.dns);
      expect(container.read(shownPageLabelProvider), PageLabel.dns);
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(pinnedTools: []));
      expect(shownItems(), isNot(contains(PageLabel.dns)));
      expect(container.read(shownPageLabelProvider), PageLabel.dashboard);
    },
  );

  test(
    'stored order ignores unknown names and duplicates and retains the settings footer',
    () {
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              sidebarOrder: [
                'requests',
                'future-tool',
                'requests',
                'settings',
                'dashboard',
              ],
            ),
          );
      final labels = shownItems();
      expect(labels.take(2), [PageLabel.requests, PageLabel.dashboard]);
      expect(labels.toSet().length, labels.length);
      expect(labels.last, PageLabel.settings);
      final settings = container
          .read(appSettingProvider)
          .copyWith(compactUi: true, pinnedTools: ['dns']);
      final restored = AppSettingProps.fromJson(
        jsonDecode(jsonEncode(settings)) as Map<String, dynamic>,
      );
      expect(restored.compactUi, isTrue);
      expect(restored.pinnedTools, ['dns']);
      expect(restored.sidebarOrder, settings.sidebarOrder);
    },
  );

  testWidgets('pin and move controls update the actual sidebar order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: NavigationSettingsView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pin-dns')));
    await tester.pumpAndSettle();
    final before = shownItems().indexOf(PageLabel.dns);
    expect(before, greaterThan(0));
    final move = find.byKey(const ValueKey('up-dns'));
    await tester.ensureVisible(move);
    await tester.tap(move);
    await tester.pumpAndSettle();
    expect(shownItems().indexOf(PageLabel.dns), before - 1);
    expect(container.read(appSettingProvider).pinnedTools, contains('dns'));
  });
}
