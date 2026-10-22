import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/quick_route_helpers.dart';
import 'package:fl_clash/views/dashboard/quick_routes_editor.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';

class QuickRoutesCard extends ConsumerWidget {
  const QuickRoutesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileId = ref.watch(currentProfileIdProvider);
    final mobile = !DashboardDensityScope.of(context).isDesktop;
    final scale = DashboardDensityScope.scaleOf(context);
    final settings = ref.watch(appSettingProvider);
    final groups = selectableQuickGroups(ref.watch(groupsProvider));
    final routes = profileId == null
        ? const <QuickRouteShortcut>[]
        : quickRoutesFor(settings, profileId);
    final rows = [
      for (final route in routes)
        _QuickRouteRow(
          key: ValueKey(route.id),
          profileId: profileId!,
          route: route,
          group: quickRouteGroup(route, groups),
        ),
    ];
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
                  onPressed: profileId == null
                      ? null
                      : () => showSheet<void>(
                          context: context,
                          builder: (_) =>
                              QuickRoutesEditor(profileId: profileId),
                        ),
                  icon: const GlyphIcon(AppGlyphs.sliders, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (routes.isEmpty)
            Text(
              profileId == null
                  ? context.appLocalizations.profiles
                  : context.appLocalizations.quickRoutesEmpty,
              style: AppTextStyle.caption1.of(context),
            )
          else if (mobile)
            Column(
              spacing: 4,
              children: [
                for (final row in rows)
                  SizedBox(height: 44 * scale, child: row),
              ],
            )
          else if (rows.length <= 3)
            Expanded(
              child: Column(
                spacing: 4,
                children: [for (final row in rows) Expanded(child: row)],
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                primary: false,
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, index) =>
                    SizedBox(height: 44 * scale, child: rows[index]),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickRouteRow extends ConsumerWidget {
  const _QuickRouteRow({
    super.key,
    required this.profileId,
    required this.route,
    required this.group,
  });

  final int profileId;
  final QuickRouteShortcut route;
  final Group? group;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final group = this.group;
    if (group == null) {
      await editQuickRoute(context, ref, profileId, route);
      return;
    }
    await showSheet<void>(
      context: context,
      builder: (sheetContext) => Consumer(
        builder: (_, sheetRef, _) {
          final sameProfile =
              sheetRef.watch(currentProfileIdProvider) == profileId;
          final current = sameProfile
              ? sheetRef.watch(groupsProvider).getGroup(group.name)
              : null;
          final names = (current?.all ?? const <Proxy>[])
              .map((proxy) => proxy.name)
              .toSet();
          final settings = sheetRef.watch(appSettingProvider);
          final historyKey = quickRouteHistoryKey(profileId, group.name);
          final favorites = (settings.quickRouteFavorites[historyKey] ?? [])
              .where(names.contains)
              .toList();
          final recents = (settings.quickRouteRecents[historyKey] ?? [])
              .where(
                (name) => names.contains(name) && !favorites.contains(name),
              )
              .toList();
          return SelectionSheet<String>(
            title: quickRouteLabel(context, route),
            sections: [
              if (favorites.isNotEmpty)
                SelectionSection(
                  label: context.appLocalizations.quickRouteFavorites,
                  items: favorites,
                ),
              if (recents.isNotEmpty)
                SelectionSection(
                  label: context.appLocalizations.quickRouteRecent,
                  items: recents,
                ),
              SelectionSection(
                label: context.appLocalizations.proxies,
                items: names
                    .where(
                      (name) =>
                          !favorites.contains(name) && !recents.contains(name),
                    )
                    .toList(),
              ),
            ],
            labelBuilder: (name) => name,
            titleBuilder: (name, title) => Row(
              children: [
                Expanded(child: title),
                Consumer(
                  builder: (_, ref, _) {
                    final delay = ref.watch(
                      delayProvider(proxyName: name, testUrl: current?.testUrl),
                    );
                    return Text(
                      delay == null
                          ? '—'
                          : delay > 0
                          ? '$delay ms'
                          : context.appLocalizations.timeout,
                      style: AppTextStyle.caption1
                          .of(context)
                          .copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                    );
                  },
                ),
                IconButton(
                  tooltip: favorites.contains(name)
                      ? context.appLocalizations.quickRouteUnfavorite
                      : context.appLocalizations.quickRouteFavorite,
                  icon: GlyphIcon(
                    AppGlyphs.star,
                    fill: favorites.contains(name) ? 1 : 0,
                    size: 18,
                  ),
                  onPressed: () {
                    sheetRef.read(appSettingProvider.notifier).update((state) {
                      final next = [
                        ...state.quickRouteFavorites[historyKey] ?? <String>[],
                      ];
                      if (!next.remove(name)) next.add(name);
                      return state.copyWith(
                        quickRouteFavorites: {
                          ...state.quickRouteFavorites,
                          historyKey: next,
                        },
                      );
                    });
                  },
                ),
              ],
            ),
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
              sheetRef.read(appSettingProvider.notifier).update((state) {
                final recent = {
                  name,
                  ...state.quickRouteRecents[historyKey] ?? <String>[],
                }.take(8).toList();
                return state.copyWith(
                  quickRouteRecents: {
                    ...state.quickRouteRecents,
                    historyKey: recent,
                  },
                );
              });
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
    final label = quickRouteLabel(context, route);
    final value = group == null
        ? context.appLocalizations.selectProxyGroup
        : selected == null || selected.isEmpty
        ? '—'
        : selected;
    final shape = AppShape.all(DashboardCorner.block);
    return Tooltip(
      message: '$label: $value',
      child: Material(
        color: DashboardColors.of(context).tone,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: () => _open(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              spacing: 6,
              children: [
                const GlyphIcon(AppGlyphs.split, size: 14),
                Expanded(
                  child: Text(
                    label,
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
