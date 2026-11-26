import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'edit.dart';
import 'layout.dart';
import 'style.dart';
import 'widget_registry.dart';
import 'widgets/widgets.dart';

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
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = sheetScrollController(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setEditing(bool editing) {
    setState(() => _editing = editing);
  }

  GlobalKey _cardKeyOf(DashboardWidget widget) =>
      _cardKeys.putIfAbsent(widget, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final platform = widget.platform ?? SupportPlatform.currentPlatform;
    final viewSize = ref.watch(viewSizeProvider);
    final sideWidth = ref.watch(sideWidthProvider);
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    final size = Size(viewSize.width - sideWidth, viewSize.height) / scale;
    final editable =
        platform != SupportPlatform.Windows &&
        !DashboardDensity.of(size).isDesktop;
    if (!editable) {
      _editing = false;
    }
    final editing = _editing;
    final gap = cardSpacingOf(context, ref.watch(viewModeProvider));
    final appLocalizations = context.appLocalizations;
    return Scaffold(
      backgroundColor: DashboardColors.of(context).page,
      title: editing
          ? appLocalizations.editDashboard
          : appLocalizations.dashboard,
      actions: [
        if (!editing) const LiveStatusButton(),
        if (editable && !editing)
          AppBarActionButton(
            data: IconButtonData(
              glyph: AppGlyphs.edit,
              tooltip: appLocalizations.editDashboard,
              onPressed: () => _setEditing(true),
            ),
          ),
      ],
      confirmationAction: editing
          ? IconButtonData(
              glyph: AppGlyphs.check,
              tooltip: appLocalizations.done,
              onPressed: () => _setEditing(false),
            )
          : null,
      // The providers learn a resize a frame late, too late for the cards.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.biggest / scale;
          final automatic = DashboardDensity.of(room);
          final layout =
              platform == SupportPlatform.Windows && !automatic.isDesktop
              ? DashboardDensity.compact
              : automatic;
          return DashboardDensityScope(
            density: layout,
            scale: scale,
            child: layout.isDesktop
                ? _DesktopDashboard(
                    platform: platform,
                    columns: dashboardColumnsOf(room.width),
                    gap: gap,
                  )
                : _MobileDashboard(
                    controller: _controller,
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
    final base = EdgeInsetsDirectional.fromSTEB(
      16,
      context.contentTopPadding,
      24,
      24 + MediaQuery.paddingOf(context).bottom,
    );
    final topHeight = (compact ? 176 : 208) * scale;
    final controlHeight = (compact ? 56 : 64) * scale;
    final pairHeight = controlHeight * 2 + gap;
    final showTunnel = platform == SupportPlatform.Windows;
    return LayoutBuilder(
      builder: (context, constraints) {
        final room =
            constraints.maxWidth - base.horizontal - gap * (columns - 1);
        final column = math.min(room / columns, _maxColumnWidth * scale);
        final inset = (room - column * columns) / 2;
        final padding = base.copyWith(
          start: base.start + inset,
          end: base.end + inset,
        );
        double span(int columns) => column * columns + gap * (columns - 1);
        Widget row(List<(int, Widget)> cards) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: gap,
          children: [
            for (final (columns, card) in cards)
              SizedBox(
                width: span(columns),
                child: RepaintBoundary(child: card),
              ),
          ],
        );
        Widget sized(double height, Widget child) =>
            SizedBox(height: height, child: child);
        final switches =
            DashboardWidget.networkTakeover.platforms.contains(platform)
            ? Column(
                spacing: gap,
                children: const [
                  Expanded(
                    child: NetworkTakeoverTile(TakeoverSwitch.systemProxy),
                  ),
                  Expanded(child: NetworkTakeoverTile(TakeoverSwitch.tun)),
                ],
              )
            : const VpnTile();
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          child: Column(
            spacing: gap,
            children: [
              if (columns == 2) ...[
                sized(
                  topHeight,
                  const RepaintBoundary(child: CurrentOutboundCard()),
                ),
                sized(
                  pairHeight,
                  row([(1, const TrafficOverviewCard()), (1, switches)]),
                ),
                sized(
                  controlHeight,
                  const RepaintBoundary(child: OutboundModeBar()),
                ),
                if (showTunnel)
                  sized(
                    controlHeight,
                    const RepaintBoundary(child: NetworkTunnelTile()),
                  ),
              ] else ...[
                sized(
                  topHeight,
                  row([
                    (2, const CurrentOutboundCard()),
                    (1, const TrafficOverviewCard()),
                    (1, switches),
                  ]),
                ),
                sized(
                  controlHeight,
                  row([
                    (2, const OutboundModeBar()),
                    if (showTunnel) (2, const NetworkTunnelTile()),
                  ]),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MobileDashboard extends ConsumerWidget {
  const _MobileDashboard({
    required this.controller,
    required this.platform,
    required this.gap,
    required this.editing,
    required this.cardKeyOf,
    required this.onDone,
  });

  final ScrollController controller;
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
    final top = context.contentTopPadding;
    final bottom = 16 + context.bottomInset;
    return CustomScrollView(
      controller: controller,
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: gap,
                  children: [
                    for (final widget in widgets)
                      _OnScreen(
                        child: RepaintBoundary(
                          key: cardKeyOf(widget),
                          child: widget.card,
                        ),
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

/// Stops a card's tickers, polls and provider updates out of view, where an
/// update still costs Impeller a frame of the whole screen.
class _OnScreen extends StatefulWidget {
  const _OnScreen({required this.child});

  final Widget child;

  @override
  State<_OnScreen> createState() => _OnScreenState();
}

class _OnScreenState extends State<_OnScreen> {
  ScrollPosition? _position;
  var _shown = true;
  var _checkPending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_checkAfterLayout);
      _position = position?..addListener(_checkAfterLayout);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_checkAfterLayout);
    super.dispose();
  }

  // Only layout places the card, and a card above can move it unscrolled.
  void _checkAfterLayout() {
    if (_checkPending) {
      return;
    }
    _checkPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkPending = false;
      _check();
    });
  }

  void _check() {
    final box = mounted ? context.findRenderObject() : null;
    if (box is! RenderBox || !box.hasSize || !box.attached) {
      return;
    }
    final RenderObject? viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is! RenderBox) {
      return;
    }
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(viewport),
      Offset.zero & box.size,
    );
    final shown = rect.overlaps(Offset.zero & viewport.size);
    if (shown != _shown) {
      setState(() => _shown = shown);
    }
  }

  @override
  Widget build(BuildContext context) {
    _checkAfterLayout();
    return TickerMode(enabled: _shown, child: widget.child);
  }
}
