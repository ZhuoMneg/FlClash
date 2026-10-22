import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class NavigationSettingsView extends ConsumerWidget {
  const NavigationSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final settings = ref.watch(appSettingProvider);
    final all = ref.watch(navigationItemsStateProvider).value;
    final ordered = orderedSidebarItems(
      all
          .where((item) => item.modes.contains(NavigationItemMode.desktop))
          .toList(),
      settings.sidebarOrder,
    ).where((item) => item.label != PageLabel.settings).toList();
    void move(int index, int delta) {
      final next = [...ordered];
      final item = next.removeAt(index);
      next.insert(index + delta, item);
      ref
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              sidebarOrder: next.map((item) => item.label.name).toList(),
            ),
          );
    }

    return BaseScaffold(
      title: l.appearanceNavigation,
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
        ).copyWith(top: context.appBarInset, bottom: 24),
        children: [
          generateSection(
            items: [
              ListItem<bool>.options(
                key: const ValueKey('ui-density'),
                title: Text(l.uiDensity),
                subtitle: Text(l.uiDensityDescription),
                options: const [false, true],
                value: settings.compactUi,
                textBuilder: (value) => value ? l.compact : l.comfortable,
                onChanged: (value) => ref
                    .read(appSettingProvider.notifier)
                    .update((state) => state.copyWith(compactUi: value)),
              ),
            ],
          ),
          if (system.isDesktop) ...[
            generateSection(
              title: l.pinnedSidebarTools,
              items: [
                for (final item in all)
                  if (const {
                    PageLabel.connections,
                    PageLabel.dns,
                    PageLabel.logs,
                  }.contains(item.label))
                    ListItem.toggle(
                      key: ValueKey('pin-${item.label.name}'),
                      leading: GlyphIcon(item.glyph),
                      title: Text(item.label.label),
                      value: settings.pinnedTools.contains(item.label.name),
                      onChanged: (value) =>
                          ref.read(appSettingProvider.notifier).update((state) {
                            final pinned = {...state.pinnedTools};
                            value
                                ? pinned.add(item.label.name)
                                : pinned.remove(item.label.name);
                            return state.copyWith(pinnedTools: pinned.toList());
                          }),
                    ),
              ],
            ),
            generateSection(
              title: l.sidebarOrder,
              items: [
                for (final (index, item) in ordered.indexed)
                  ListItem(
                    key: ValueKey('order-${item.label.name}'),
                    leading: GlyphIcon(item.glyph),
                    title: Text(item.label.label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: ValueKey('up-${item.label.name}'),
                          tooltip: l.moveUp,
                          icon: const GlyphIcon(AppGlyphs.chevronUp),
                          onPressed: index == 0 ? null : () => move(index, -1),
                        ),
                        IconButton(
                          key: ValueKey('down-${item.label.name}'),
                          tooltip: l.moveDown,
                          icon: const GlyphIcon(AppGlyphs.chevronDown),
                          onPressed: index == ordered.length - 1
                              ? null
                              : () => move(index, 1),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
