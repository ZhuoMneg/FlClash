import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import 'card.dart';

Glyph _glyphOf(Mode mode) => switch (mode) {
  Mode.rule => AppGlyphs.rules,
  Mode.global => AppGlyphs.proxies,
  Mode.direct => AppGlyphs.target,
};

void _changeMode(WidgetRef ref, Mode mode) {
  if (ref.read(patchClashConfigProvider).mode == mode) return;
  ref.read(setupActionProvider.notifier).changeMode(mode);
}

class OutboundModeCard extends ConsumerWidget {
  const OutboundModeCard({super.key});

  static const _outer = 26.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final tone = DashboardColors.of(context).tone;
    final style = AppTextStyle.footnote.of(context, emphasized: true);
    return DashboardCard(
      semanticLabel: context.appLocalizations.outboundMode,
      child: Column(
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.split,
            title: context.appLocalizations.outbound,
          ),
          const SizedBox(height: 12),
          ConnectedButtonGroup(
            children: [
              for (final (index, item) in Mode.values.indexed)
                Expanded(
                  child: ConnectedButton(
                    selected: item == mode,
                    first: index == 0,
                    last: index == Mode.values.length - 1,
                    outer: _outer,
                    inner: 12,
                    background: tone,
                    semanticLabel: item.label,
                    onTap: () => _changeMode(ref, item),
                    builder: (foreground) => SizedBox(
                      height: 52,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 2,
                        children: [
                          GlyphIcon(
                            _glyphOf(item),
                            size: 18,
                            color: foreground,
                          ),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(color: foreground),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class OutboundModeBar extends ConsumerWidget {
  const OutboundModeBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final l = context.appLocalizations;
    final tone = DashboardColors.of(context).tone2;
    return DashboardCard(
      semanticLabel: l.outboundMode,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Text(l.outboundMode, style: DashboardText.rowTitle(context)),
          DecoratedBox(
            decoration: ShapeDecoration(color: tone, shape: AppShape.all(18)),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: ConnectedButtonGroup(
                children: [
                  for (final item in Mode.values)
                    Expanded(
                      child: ConnectedButton(
                        selected: item == mode,
                        first: true,
                        last: true,
                        outer: 14,
                        inner: 14,
                        background: tone,
                        semanticLabel: item.label,
                        onTap: () => _changeMode(ref, item),
                        builder: (foreground) => Container(
                          constraints: BoxConstraints(
                            minHeight:
                                38 * DashboardDensityScope.scaleOf(context),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.subheadline
                                .of(context, emphasized: true)
                                .copyWith(color: foreground),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Text(switch (mode) {
            Mode.rule => l.dashboardRuleModeDescription,
            Mode.global => l.dashboardGlobalModeDescription,
            Mode.direct => l.dashboardDirectModeDescription,
          }, style: DashboardText.label(context)),
        ],
      ),
    );
  }
}
