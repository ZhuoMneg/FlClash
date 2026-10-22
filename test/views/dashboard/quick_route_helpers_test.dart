import 'dart:convert';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/views/dashboard/quick_route_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

Group _group(String name, {GroupType type = GroupType.Selector}) =>
    Group(name: name, type: type, all: const []);

void main() {
  test(
    'legacy bindings are read without overwriting per-profile routes or an intentionally empty list',
    () {
      const custom = QuickRouteShortcut(
        id: 'custom',
        label: 'Work',
        groupName: 'Office',
      );
      const settings = AppSettingProps(
        dashboardQuickGroups: {'proxy': 'Legacy'},
        profileQuickRoutes: {
          '10': [custom],
          '20': [],
        },
      );
      expect(quickRoutesFor(settings, 10), [custom]);
      expect(quickRoutesFor(settings, 20), isEmpty);
      final fallback = quickRoutesFor(settings, 30);
      expect(fallback.map((route) => route.id), ['dmit', 'proxy', 'emby']);
      expect(
        fallback.singleWhere((route) => route.id == 'proxy').groupName,
        'Legacy',
      );
      expect(settings.profileQuickRoutes, {
        '10': [custom],
        '20': [],
      });
    },
  );

  test(
    'per-profile shortcuts, favorites and recents survive a settings round trip independently',
    () {
      final a = quickRouteHistoryKey(1, 'Proxy');
      final b = quickRouteHistoryKey(2, 'Proxy');
      final settings = AppSettingProps(
        profileQuickRoutes: const {
          '1': [QuickRouteShortcut(id: 'a', label: 'A', groupName: 'Proxy')],
          '2': [QuickRouteShortcut(id: 'b', label: 'B', groupName: 'Proxy')],
        },
        quickRouteFavorites: {
          a: ['Node A'],
          b: ['Node B'],
        },
        quickRouteRecents: {
          a: ['Node C'],
        },
      );
      final restored = AppSettingProps.fromJson(
        jsonDecode(jsonEncode(settings)) as Map<String, dynamic>,
      );
      expect(quickRoutesFor(restored, 1).single.label, 'A');
      expect(quickRoutesFor(restored, 2).single.label, 'B');
      expect(restored.quickRouteFavorites[a], ['Node A']);
      expect(restored.quickRouteFavorites[b], ['Node B']);
      expect(restored.quickRouteRecents[b], isNull);
      expect(a, isNot(b));
    },
  );

  test(
    'automatic matching handles decorated names and refuses ambiguous groups',
    () {
      const route = QuickRouteShortcut(id: 'proxy');
      final decorated = _group('🌐 Proxy');
      expect(quickRouteGroup(route, [decorated]), decorated);
      expect(quickRouteGroup(route, [decorated, _group('🚀 Proxy')]), isNull);
      expect(
        quickRouteGroup(const QuickRouteShortcut(id: 'new'), [decorated]),
        isNull,
      );
    },
  );

  test('an explicit binding never silently falls back to another group', () {
    const route = QuickRouteShortcut(id: 'proxy', groupName: 'Removed');
    expect(quickRouteGroup(route, [_group('Proxy')]), isNull);
    final exact = _group('Removed');
    expect(quickRouteGroup(route, [_group('Proxy'), exact]), exact);
  });

  test('pickable groups exclude GLOBAL and nonselectable groups', () {
    final groups = [
      _group('GLOBAL'),
      _group('Manual'),
      _group('Automatic', type: GroupType.URLTest),
      _group('Relay', type: GroupType.Relay),
    ];
    expect(selectableQuickGroups(groups).map((group) => group.name), [
      'Manual',
      'Automatic',
    ]);
  });
}
