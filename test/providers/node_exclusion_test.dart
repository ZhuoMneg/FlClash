import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'name filtering does not restart on selection or ordering changes',
    () async {
      const group = Group(
        name: 'Proxy',
        type: GroupType.Selector,
        now: 'Tokyo',
        hidden: false,
        all: [
          Proxy(name: 'Tokyo', type: 'ss'),
          Proxy(name: 'expires tomorrow', type: 'ss'),
        ],
      );
      final container = ProviderContainer(
        overrides: [selectedMapProvider.overrideWithValue(const {})],
      );
      addTearDown(container.dispose);
      container.read(groupsProvider.notifier).value = [group];
      final states = <AsyncValue<Set<String>>>[];
      final subscription = container.listen(
        excludedProxyNamesProvider,
        (_, next) => states.add(next),
      );
      addTearDown(subscription.close);
      container
          .read(proxiesStyleSettingProvider.notifier)
          .update((state) => state.copyWith(nodeExcludeFilter: 'expire'));
      await container.read(excludedProxyNamesProvider.future);
      await container.pump();
      states.clear();

      container.read(groupsProvider.notifier).value = [
        group.copyWith(
          now: 'expires tomorrow',
          all: group.all.reversed.toList(),
        ),
      ];
      await container.pump();
      expect(states, isEmpty);
      expect(container.read(excludedProxyNamesProvider).value, {
        'expires tomorrow',
      });
    },
  );

  test(
    'recalculation keeps prior exclusions until new names have been matched',
    () async {
      const group = Group(
        name: 'Proxy',
        type: GroupType.Selector,
        now: 'Tokyo',
        hidden: false,
        all: [
          Proxy(name: 'Tokyo', type: 'ss'),
          Proxy(name: 'expires tomorrow', type: 'ss'),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          currentGroupsStateProvider.overrideWithValue(
            const GroupsState(value: [group]),
          ),
          selectedMapProvider.overrideWithValue(const {}),
        ],
      );
      addTearDown(container.dispose);
      container.read(groupsProvider.notifier).value = [group];
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

      container.read(groupsProvider.notifier).value = [
        group.copyWith(
          all: [
            ...group.all,
            const Proxy(name: 'London', type: 'ss'),
          ],
        ),
      ];
      final visible = container
          .read(nodeFilteredGroupsStateProvider)
          .value
          .single
          .all;
      expect(visible.map((proxy) => proxy.name), ['Tokyo']);
      await container.read(excludedProxyNamesProvider.future);
    },
  );

  test('plain text mode is passed through to name matching', () async {
    const group = Group(
      name: 'Proxy',
      type: GroupType.Selector,
      now: 'Tokyo',
      all: [
        Proxy(name: '[info]', type: 'ss'),
        Proxy(name: 'Tokyo', type: 'ss'),
      ],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(groupsProvider.notifier).value = [group];
    final subscription = container.listen(
      excludedProxyNamesProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            nodeExcludeFilter: '[info]',
            nodeExcludePlainText: true,
          ),
        );
    expect(await container.read(excludedProxyNamesProvider.future), {'[info]'});
  });

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
