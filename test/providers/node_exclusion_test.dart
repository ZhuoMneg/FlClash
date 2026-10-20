import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'exclusion changes and clearing update both normal and searched lists',
    () async {
      const groups = [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          now: 'Tokyo',
          hidden: false,
          all: [
            Proxy(name: 'Tokyo', type: 'ss'),
            Proxy(name: 'expires tomorrow', type: 'ss'),
          ],
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          currentGroupsStateProvider.overrideWithValue(
            const GroupsState(value: groups),
          ),
          selectedMapProvider.overrideWithValue(const {}),
        ],
      );
      addTearDown(container.dispose);
      container.read(groupsProvider.notifier).value = groups;
      final subscription = container.listen(
        nodeFilteredGroupsStateProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      container
          .read(proxiesStyleSettingProvider.notifier)
          .update((state) => state.copyWith(nodeExcludeFilter: 'expire'));
      await container.read(excludedProxyNamesProvider.future);
      await container.pump();
      expect(
        container
            .read(visibleGroupsStateProvider)
            .value
            .single
            .all
            .map((proxy) => proxy.name),
        ['Tokyo'],
      );
      expect(
        container.read(filterGroupsStateProvider('expire')).value,
        isEmpty,
      );
      container
          .read(proxiesStyleSettingProvider.notifier)
          .update((state) => state.copyWith(nodeExcludeFilter: ''));
      await container.read(excludedProxyNamesProvider.future);
      await container.pump();
      expect(
        container.read(visibleGroupsStateProvider).value.single.all,
        hasLength(2),
      );
    },
  );
}
