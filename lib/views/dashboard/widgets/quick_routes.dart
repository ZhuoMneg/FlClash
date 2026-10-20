import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';

enum _QuickRoute {
  dmit,
  proxy,
  emby;

  String label(BuildContext context) => switch (this) {
    dmit => context.appLocalizations.dmitProtocol,
    proxy => context.appLocalizations.proxyExit,
    emby => context.appLocalizations.embyExit,
  };

  Glyph get glyph => switch (this) {
    dmit => AppGlyphs.vpn,
    proxy => AppGlyphs.proxies,
    emby => AppGlyphs.requests,
  };

  List<String> get aliases => switch (this) {
    dmit => ['dmit前置协议', 'dmit协议', 'dmit前置', 'dmitprotocol', 'dmit'],
    proxy => ['proxy', 'proxy出口'],
    emby => ['emby', 'emby出口'],
  };
}

String _normalized(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');

List<Group> _selectableGroups(WidgetRef ref) => ref
    .watch(groupsProvider)
    .where(
      (group) =>
          group.type == GroupType.Selector || group.type.isComputedSelected,
    )
    .where((group) => group.name != GroupName.GLOBAL.name)
    .toList();

Group? _groupFor(
  _QuickRoute route,
  List<Group> groups,
  Map<String, String> bindings,
) {
  final bound = bindings[route.name];
  if (bound != null) return groups.getGroup(bound);
  for (final alias in route.aliases) {
    final matches = groups
        .where((group) => _normalized(group.name) == alias)
        .toList();
    if (matches.length == 1) return matches.single;
  }
  return null;
}

Future<void> _bindRoute(
  BuildContext context,
  WidgetRef ref,
  _QuickRoute route,
) async {
  final value = await showSheet<String>(
    context: context,
    builder: (sheetContext) => Consumer(
      builder: (_, sheetRef, _) {
        final groups = _selectableGroups(sheetRef);
        return SelectionSheet<String>(
          title: route.label(context),
          sections: [
            SelectionSection(items: groups.map((group) => group.name).toList()),
          ],
          labelBuilder: (name) => name,
          selectedOf: (ref) => _groupFor(
            route,
            groups,
            ref.watch(appSettingProvider).dashboardQuickGroups,
          )?.name,
          onSelected: (name) => Navigator.of(sheetContext).pop(name),
        );
      },
    ),
  );
  if (value == null || !context.mounted) return;
  ref
      .read(appSettingProvider.notifier)
      .update(
        (state) => state.copyWith(
          dashboardQuickGroups: {
            ...state.dashboardQuickGroups,
            route.name: value,
          },
        ),
      );
}

class QuickRoutesCard extends ConsumerWidget {
  const QuickRoutesCard({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final route = await showSheet<_QuickRoute>(
      context: context,
      builder: (sheetContext) => SelectionSheet<_QuickRoute>(
        title: context.appLocalizations.quickRoutes,
        sections: const [SelectionSection(items: _QuickRoute.values)],
        labelBuilder: (route) => route.label(context),
        selectedOf: (_) => null,
        onSelected: (route) => Navigator.of(sheetContext).pop(route),
      ),
    );
    if (route != null && context.mounted) await _bindRoute(context, ref, route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mobile = !DashboardDensityScope.of(context).isDesktop;
    final scale = DashboardDensityScope.scaleOf(context);
    final groups = _selectableGroups(ref);
    final bindings = ref.watch(appSettingProvider).dashboardQuickGroups;
    return DashboardCard(
      semanticLabel: context.appLocalizations.quickRoutes,
      child: Column(
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.split,
            title: context.appLocalizations.quickRoutes,
            trailing: [
              CommonMinIconButtonTheme(
                child: IconButton(
                  tooltip: context.appLocalizations.edit,
                  onPressed: () => _edit(context, ref),
                  icon: const GlyphIcon(AppGlyphs.sliders, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final route in _QuickRoute.values) ...[
            if (route != _QuickRoute.dmit) const SizedBox(height: 4),
            if (mobile)
              SizedBox(
                height: 44 * scale,
                child: _QuickRouteRow(
                  route: route,
                  group: _groupFor(route, groups, bindings),
                ),
              )
            else
              Expanded(
                child: _QuickRouteRow(
                  route: route,
                  group: _groupFor(route, groups, bindings),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _QuickRouteRow extends ConsumerWidget {
  const _QuickRouteRow({required this.route, required this.group});

  final _QuickRoute route;
  final Group? group;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final group = this.group;
    if (group == null) {
      await _bindRoute(context, ref, route);
      return;
    }
    final profileId = ref.read(currentProfileIdProvider);
    await showSheet<void>(
      context: context,
      builder: (sheetContext) => Consumer(
        builder: (_, sheetRef, _) {
          final current = sheetRef.watch(groupsProvider).getGroup(group.name);
          return SelectionSheet<String>(
            title: route.label(context),
            sections: [
              SelectionSection(
                items: (current?.all ?? const <Proxy>[])
                    .map((proxy) => proxy.name)
                    .toList(),
              ),
            ],
            labelBuilder: (name) => name,
            selectedOf: (ref) =>
                ref.watch(selectedProxyNameProvider(group.name)),
            onSelected: (name) {
              final active = sheetRef.read(groupsProvider).getGroup(group.name);
              if (sheetRef.read(currentProfileIdProvider) != profileId ||
                  active == null ||
                  !active.all.any((proxy) => proxy.name == name)) {
                return;
              }
              selectGroupProxy(
                sheetRef,
                groupName: active.name,
                groupType: active.type,
                proxyName: name,
              );
              Navigator.of(sheetContext).pop();
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = this.group;
    final selected = group == null
        ? null
        : ref.watch(selectedProxyNameProvider(group.name));
    final value = group == null
        ? context.appLocalizations.selectProxyGroup
        : selected == null || selected.isEmpty
        ? '—'
        : selected;
    final colors = DashboardColors.of(context);
    final shape = AppShape.all(DashboardCorner.block);
    return Tooltip(
      message: '${route.label(context)}: $value',
      child: Material(
        color: colors.tone,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: () => _open(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              spacing: 6,
              children: [
                GlyphIcon(
                  route.glyph,
                  size: 14,
                  color: context.colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Text(
                    route.label(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption1.of(context),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: EmojiText(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                  ),
                ),
                const GlyphIcon(AppGlyphs.chevronDown, size: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
