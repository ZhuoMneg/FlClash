import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'edit.dart';
import 'layout.dart';
import 'style.dart';
import 'widget_registry.dart';
import 'widgets/core_status_button.dart';
import 'widgets/widgets.dart';

const _memoryColumnMin = 290.0;

const _maxColumnWidth = 440.0;

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key, this.platform});

  /// The host's platform when null.
  final SupportPlatform? platform;

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  var _editing = false;
  final _cardKeys = <DashboardWidget, GlobalKey>{};

  void _setEditing(bool editing) {
    setState(() => _editing = editing);
  }

  GlobalKey _cardKeyOf(DashboardWidget widget) =>
      _cardKeys.putIfAbsent(widget, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final platform = widget.platform ?? SupportPlatform.currentPlatform;
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    final editing = _editing;
    final customized = ref.watch(
      appSettingProvider.select((state) => state.desktopDashboardCustomized),
    );
    final compactUi = ref.watch(
      appSettingProvider.select((state) => state.compactUi),
    );
    final gap = cardSpacingOf(context, ref.watch(viewModeProvider));
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      backgroundColor: DashboardColors.of(context).page,
      title: editing
          ? appLocalizations.editDashboard
          : appLocalizations.dashboard,
      backAction: editing ? () => _setEditing(false) : null,
      actions: [if (!editing && coreLib == null) const CoreStatusButton()],
      confirmationAction: editing
          ? IconButtonData(
              glyph: AppGlyphs.check,
              tooltip: appLocalizations.done,
              onPressed: () => _setEditing(false),
            )
          : null,
      iconActions: [
        if (!editing)
          IconButtonData(
            glyph: AppGlyphs.edit,
            tooltip: appLocalizations.editDashboard,
            onPressed: () => _setEditing(true),
          ),
      ],
      menuItems: [
        CommonPopupMenuItem(
          glyph: AppGlyphs.reset,
          label: appLocalizations.reset,
          onPressed: () {
            ref
                .read(appSettingProvider.notifier)
                .update(
                  (state) => state.copyWith(
                    dashboardWidgets: defaultDashboardWidgets,
                    desktopDashboardCustomized: false,
                  ),
                );
            _setEditing(false);
          },
        ),
      ],
      // The providers learn a resize a frame late, too late for the cards.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.biggest / scale;
          final automatic = DashboardDensity.of(room);
          final layout = editing
              ? DashboardDensity.mobile
              : compactUi && automatic.isDesktop
              ? DashboardDensity.compact
              : automatic;
          return DashboardDensityScope(
            density: layout,
            scale: scale,
            child: layout.isDesktop
                ? customized
                      ? _CustomDesktopDashboard(
                          platform: platform,
                          columns: dashboardColumnsOf(room.width),
                          gap: gap,
                        )
                      : _DesktopDashboard(
                          platform: platform,
                          columns: dashboardColumnsOf(room.width),
                          gap: gap,
                        )
                : _MobileDashboard(
                    platform: platform,
                    gap: gap,
                    editing: editing,
                    cardKeyOf: _cardKeyOf,
                    onDone: () => _setEditing(false),
                  ),
          );
        },
      ),
    );
  }
}

class _DesktopDashboard extends StatelessWidget {
  const _DesktopDashboard({
    required this.platform,
    required this.columns,
    required this.gap,
  });
  final SupportPlatform platform;
  final int columns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final density = DashboardDensityScope.of(context);
    final compact = density.isCompact;
    final scale = DashboardDensityScope.scaleOf(context);
    final topHeight = (compact ? 176 : 208) * scale;
    final controlHeight = (compact ? 56 : 64) * scale;
    final middleHeight = (compact ? 152 : 176) * scale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final base = EdgeInsetsDirectional.fromSTEB(
          16,
          context.contentTopPadding,
          24,
          24 + context.bottomInset,
        );
        final room =
            constraints.maxWidth - base.horizontal - gap * (columns - 1);
        final column = math.min(room / columns, _maxColumnWidth * scale);
        final inset = (room - column * columns) / 2;
        final padding = base.copyWith(
          start: base.start + inset,
          end: base.end + inset,
        );
        double span(int count) => column * count + gap * (count - 1);
        Widget row(List<(int, Widget)> cards) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: gap,
          children: [
            for (final (count, card) in cards)
              SizedBox(
                width: span(count),
                child: RepaintBoundary(child: card),
              ),
          ],
        );
        Widget sized(double height, Widget child) =>
            SizedBox(height: height, child: child);
        final switches =
            DashboardWidget.networkTakeover.platforms.contains(platform)
            ? const [
                (1, NetworkTakeoverTile(TakeoverSwitch.systemProxy)),
                (1, NetworkTakeoverTile(TakeoverSwitch.tun)),
              ]
            : const [(2, VpnTile())];
        final tallGroups =
            columns == 2 ||
            constraints.maxHeight >=
                padding.vertical +
                    topHeight +
                    controlHeight +
                    middleHeight +
                    gap * 3 +
                    160 * scale;
        final groups = tallGroups
            ? const ProxyGroupsCard()
            : const ProxyGroupsSummaryCard();
        return SingleChildScrollView(
          padding: padding,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            spacing: gap,
            children: [
              if (columns == 2) ...[
                sized(topHeight, const CurrentOutboundCard()),
                sized(
                  topHeight,
                  row(const [
                    (1, SpeedCard(direction: TrafficDirection.upload)),
                    (1, SpeedCard(direction: TrafficDirection.download)),
                  ]),
                ),
                sized(controlHeight, const OutboundModeBar()),
                sized(controlHeight, row(switches)),
                sized(
                  middleHeight,
                  row(const [(1, IntranetIpCard()), (1, MemoryInfo())]),
                ),
                sized(middleHeight, const ProfilesCard()),
              ] else ...[
                sized(
                  topHeight,
                  row(const [
                    (2, CurrentOutboundCard()),
                    (1, SpeedCard(direction: TrafficDirection.upload)),
                    (1, SpeedCard(direction: TrafficDirection.download)),
                  ]),
                ),
                sized(
                  controlHeight,
                  row([(2, const OutboundModeBar()), ...switches]),
                ),
                sized(
                  middleHeight,
                  row([
                    (
                      column >= _memoryColumnMin * scale ? 1 : 2,
                      const IntranetIpCard(),
                    ),
                    (2, const ProfilesCard()),
                    if (column >= _memoryColumnMin * scale)
                      (1, const MemoryInfo()),
                  ]),
                ),
              ],
              sized((tallGroups ? (compact ? 224 : 256) : 112) * scale, groups),
            ],
          ),
        );
      },
    );
  }
}

class _MobileDashboard extends ConsumerWidget {
  const _MobileDashboard({
    required this.platform,
    required this.gap,
    required this.editing,
    required this.cardKeyOf,
    required this.onDone,
  });

  final SupportPlatform platform;
  final double gap;
  final bool editing;
  final GlobalKey Function(DashboardWidget widget) cardKeyOf;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(
      dashboardStateProvider.select((state) => state.dashboardWidgets),
    );
    final top = MediaQuery.paddingOf(context).top + 4;
    final bottom = 16 + BottomInsetScope.of(context);
    return CustomScrollView(
      // A viewport per card lays them all out and holds the scroll end still.
      scrollCacheExtent: editing
          ? ScrollCacheExtent.viewport(DashboardWidget.values.length.toDouble())
          : null,
      slivers: [
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final side = dashboardMobileSideOf(constraints.crossAxisExtent);
            final widgets = [
              for (final widget in saved)
                if (widget.platforms.contains(platform)) widget,
            ];
            if (editing) {
              return DashboardEditor(
                platform: platform,
                widgets: widgets,
                cardKeyOf: cardKeyOf,
                padding: EdgeInsets.fromLTRB(side, top, side, bottom),
                gap: gap,
                onDone: onDone,
              );
            }
            return SliverPadding(
              padding: EdgeInsets.fromLTRB(side, top, side, bottom),
              // A lazy list estimates the cards it has not laid out from the
              // ones it has; cards this uneven move the scroll end as it goes.
              sliver: SliverToBoxAdapter(
                child: Column(
                  spacing: gap,
                  children: [
                    for (final widget in widgets)
                      RepaintBoundary(
                        key: cardKeyOf(widget),
                        child: widget.card,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CustomDesktopDashboard extends ConsumerWidget {
  const _CustomDesktopDashboard({
    required this.platform,
    required this.columns,
    required this.gap,
  });

  final SupportPlatform platform;
  final int columns;
  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = DashboardDensityScope.scaleOf(context);
    final saved = ref.watch(
      dashboardStateProvider.select((state) => state.dashboardWidgets),
    );
    final cards = [
      for (final card in saved)
        if (card.platforms.contains(platform)) card,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - 32 - gap * (columns - 1);
        final unit = available / columns;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final card in cards)
                SizedBox(
                  key: ValueKey('desktop-${card.name}'),
                  width: unit * _span(card) + gap * (_span(card) - 1),
                  height: _height(card) * scale,
                  child: RepaintBoundary(
                    child: card == DashboardWidget.networkSpeed
                        ? Row(
                            spacing: gap,
                            children: const [
                              Expanded(
                                child: SpeedCard(
                                  direction: TrafficDirection.upload,
                                ),
                              ),
                              Expanded(
                                child: SpeedCard(
                                  direction: TrafficDirection.download,
                                ),
                              ),
                            ],
                          )
                        : card.card,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  int _span(DashboardWidget card) => switch (card) {
    DashboardWidget.currentOutbound ||
    DashboardWidget.networkSpeed ||
    DashboardWidget.proxyGroups ||
    DashboardWidget.connectionStats => 2,
    _ => 1,
  };

  double _height(DashboardWidget card) => switch (card) {
    DashboardWidget.currentOutbound || DashboardWidget.networkSpeed => 224,
    DashboardWidget.proxyGroups => 320,
    DashboardWidget.outboundMode || DashboardWidget.vpnButton => 144,
    _ => 224,
  };
}
