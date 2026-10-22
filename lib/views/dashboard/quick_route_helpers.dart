import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:material_ui/material_ui.dart';

const defaultQuickRoutes = [
  QuickRouteShortcut(id: 'dmit'),
  QuickRouteShortcut(id: 'proxy'),
  QuickRouteShortcut(id: 'emby'),
];

List<QuickRouteShortcut> quickRoutesFor(
  AppSettingProps settings,
  int profileId,
) =>
    settings.profileQuickRoutes['$profileId'] ??
    [
      for (final route in defaultQuickRoutes)
        route.copyWith(
          groupName: settings.dashboardQuickGroups[route.id] ?? '',
        ),
    ];

String quickRouteLabel(BuildContext context, QuickRouteShortcut route) {
  if (route.label.isNotEmpty) return route.label;
  return switch (route.id) {
    'dmit' => context.appLocalizations.dmitProtocol,
    'proxy' => context.appLocalizations.proxyExit,
    'emby' => context.appLocalizations.embyExit,
    _ => route.id,
  };
}

List<Group> selectableQuickGroups(List<Group> groups) => groups
    .where(
      (group) =>
          group.name != GroupName.GLOBAL.name &&
          (group.type == GroupType.Selector || group.type.isComputedSelected),
    )
    .toList();

Group? quickRouteGroup(QuickRouteShortcut route, List<Group> groups) {
  if (route.groupName.isNotEmpty) return groups.getGroup(route.groupName);
  final aliases = switch (route.id) {
    'dmit' => ['dmit前置协议', 'dmit协议', 'dmit前置', 'dmitprotocol', 'dmit'],
    'proxy' => ['proxy', 'proxy出口'],
    'emby' => ['emby', 'emby出口'],
    _ => const <String>[],
  };
  for (final alias in aliases) {
    final matches = groups.where(
      (group) =>
          group.name.toLowerCase().replaceAll(
            RegExp(r'[^a-z0-9\u4e00-\u9fff]'),
            '',
          ) ==
          alias,
    );
    if (matches.length == 1) return matches.single;
  }
  return null;
}

String quickRouteHistoryKey(int profileId, String groupName) =>
    '$profileId:$groupName';
