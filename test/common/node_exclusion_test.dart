import 'package:fl_clash/common/compute.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plain text matches regex punctuation literally and ignores case', () {
    expect(
      matchProxyNameFilter((
        pattern: '[Info]',
        names: ['[INFO] remaining', 'Tokyo', 'Info plain'],
        plainText: true,
      )),
      {'[INFO] remaining'},
    );
    expect(
      matchProxyNameFilter((pattern: '', names: ['Tokyo'], plainText: true)),
      isEmpty,
    );
  });

  test('filter names ignore selection, ordering and duplicate memberships', () {
    const group = Group(
      name: 'Proxy',
      type: GroupType.Selector,
      now: 'Tokyo',
      all: [
        Proxy(name: 'Tokyo', type: 'ss'),
        Proxy(name: 'Paris', type: 'ss'),
      ],
    );
    expect(
      ProxyFilterNames([group]),
      ProxyFilterNames([
        group.copyWith(now: 'Paris', all: group.all.reversed.toList()),
        group,
      ]),
    );
  });

  test('node-name regex handles Unicode and ignores case', () {
    expect(
      matchExcludedProxyNames((
        pattern: '剩余|expire',
        names: ['剩余流量', 'Expires tomorrow', 'Tokyo'],
      )),
      {'剩余流量', 'Expires tomorrow'},
    );
    expect(matchExcludedProxyNames((pattern: '[', names: ['Tokyo'])), isEmpty);
  });

  test(
    'filter keeps the active node and group navigation without changing sources',
    () {
      const group = Group(
        name: 'Proxy',
        type: GroupType.Selector,
        now: 'expired-active',
        all: [
          Proxy(name: 'expired-active', type: 'ss'),
          Proxy(name: 'expired-unused', type: 'ss'),
          Proxy(name: 'expired-group', type: 'Selector'),
          Proxy(name: 'Tokyo', type: 'ss'),
        ],
      );
      const nested = Group(
        name: 'expired-group',
        type: GroupType.Selector,
        all: [],
      );
      final visible = computeExcludeProxies(
        groups: [group],
        allGroups: [group, nested],
        excluded: {'expired-active', 'expired-unused', 'expired-group'},
        selectedMap: {},
      );
      expect(visible.single.all.map((proxy) => proxy.name), [
        'expired-active',
        'expired-group',
        'Tokyo',
      ]);
      expect(group.all, hasLength(4));
    },
  );

  test('saved selection wins for selector groups', () {
    const group = Group(
      name: 'Proxy',
      type: GroupType.Selector,
      now: 'old',
      all: [
        Proxy(name: 'old', type: 'ss'),
        Proxy(name: 'saved', type: 'ss'),
      ],
    );
    final visible = computeExcludeProxies(
      groups: [group],
      allGroups: [group],
      excluded: {'old', 'saved'},
      selectedMap: {'Proxy': 'saved'},
    );
    expect(visible.single.all.single.name, 'saved');
  });

  test(
    'URLTest preserves its actual choice instead of a preferred fallback',
    () {
      const group = Group(
        name: 'Auto',
        type: GroupType.URLTest,
        now: 'actual',
        all: [
          Proxy(name: 'actual', type: 'ss'),
          Proxy(name: 'preferred', type: 'ss'),
        ],
      );
      final visible = computeExcludeProxies(
        groups: [group],
        allGroups: [group],
        excluded: {'actual', 'preferred'},
        selectedMap: {'Auto': 'preferred'},
      );
      expect(visible.single.all.single.name, 'actual');
    },
  );

  test('node exclusion survives backup JSON serialization', () {
    const style = ProxiesStyleProps(nodeExcludeFilter: '剩余|expire');
    expect(
      ProxiesStyleProps.fromJson(style.toJson()).nodeExcludeFilter,
      style.nodeExcludeFilter,
    );
    expect(ProxiesStyleProps.fromJson({}).nodeExcludeFilter, isEmpty);
  });
}
