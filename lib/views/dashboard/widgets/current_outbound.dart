import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/features/ip_quality/labels.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/shapes/shapes.dart';

import 'card.dart';
import 'package:prism_ui/prism_ui.dart';

const _builtinOutbounds = {'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS'};

bool isBuiltinOutbound(String name) => _builtinOutbounds.contains(name);

const _ipMask = '*****';

const _decorationGrowth = 0.12;

const _decorationTurn = 2 * math.pi / 12;

/// The address the proxied traffic leaves by, next to the start button.
class CurrentOutboundCard extends ConsumerStatefulWidget {
  const CurrentOutboundCard({super.key}) : _overview = false;
  const CurrentOutboundCard.overview({super.key}) : _overview = true;

  final bool _overview;

  @override
  ConsumerState<CurrentOutboundCard> createState() =>
      _CurrentOutboundCardState();
}

class _CurrentOutboundCardState extends ConsumerState<CurrentOutboundCard> {
  late final OutboundIpProbe _probe;

  @override
  void initState() {
    super.initState();
    _probe = ref.read(outboundIpProbeProvider.notifier)..watch(routedOutbound);
  }

  @override
  void dispose() {
    _probe.unwatch(routedOutbound);
    super.dispose();
  }

  void _refresh(String? ip) {
    _probe.refresh(const [routedOutbound]);
    if (ip != null && ref.read(ipQualityProvider(ip)).hasError) {
      ref.invalidate(ipQualityProvider(ip));
    }
  }

  @override
  Widget build(BuildContext context) {
    final density = DashboardDensityScope.of(context);
    final hasProfile = ref.watch(
      profilesProvider.select((state) => state.isNotEmpty),
    );
    final isStart = ref.watch(isStartProvider);
    final suspended = isStart && ref.watch(suspendProvider);
    final rootAccess =
        rsFeature && (ref.watch(rootAccessProvider).value ?? false);
    final entry = ref.watch(
      outboundIpProbeProvider.select((state) => state.entryOf(routedOutbound)),
    );
    final ipInfo = entry.value;
    final phase = entry.phase;
    final failed = phase == ProbePhase.failed && ipInfo == null;
    final qualityState = widget._overview || ipInfo == null
        ? null
        : ref.watch(ipQualityProvider(ipInfo.ip));
    final quality = qualityState?.value;
    final qualityLoading =
        qualityState != null && quality == null && qualityState.isLoading;
    final loading = ipInfo == null ? !failed : qualityLoading;
    final metrics = _OutboundMetrics.of(density);
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final (chipLabel, chipTone) = suspended
        ? (appLocalizations.suspended, DashboardChipTone.warn)
        : isStart
        ? (appLocalizations.running, DashboardChipTone.ok)
        : (appLocalizations.notRunning, DashboardChipTone.idle);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: rootAccess ? 1 : 0),
      duration: context.motionDuration(commonDuration),
      builder: (context, root, child) => DashboardCard(
        padding: EdgeInsets.zero,
        semanticLabel: rootAccess
            ? '${appLocalizations.status} ${appLocalizations.root}'
            : appLocalizations.status,
        side: root == 0
            ? BorderSide.none
            : BorderSide(
                color: context.colorScheme.primary.withValues(alpha: root),
                width: 1.5,
              ),
        child: child!,
      ),
      child: widget._overview
          ? _OverviewHero(
              running: isStart,
              suspended: suspended,
              enabled: hasProfile,
              ip: ipInfo?.ip,
              onRefresh: () => _refresh(ipInfo?.ip),
              label: chipLabel,
              tone: chipTone,
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: ClipPath(
                    clipper: ShapeBorderClipper(
                      shape: AppShape.all(dashboardCardRadius(density)),
                      textDirection: Directionality.of(context),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        PositionedDirectional(
                          end: metrics.decorationEnd,
                          top: metrics.decorationTop,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: isStart ? 1 : 0),
                            duration: context.motionDuration(_morphDuration),
                            curve: Curves.easeOutBack,
                            builder: (_, progress, _) => Transform.rotate(
                              angle: _decorationTurn * progress,
                              child: Transform.scale(
                                scale: 1 + _decorationGrowth * progress,
                                child: ShapeBadge(
                                  shape: MaterialShapes.cookie12Sided,
                                  color: Color.lerp(
                                    colorScheme.brightness == Brightness.light
                                        ? Color.alphaBlend(
                                            colorScheme.primary.withValues(
                                              alpha: 0.08,
                                            ),
                                            colors.card,
                                          )
                                        : colors.tone,
                                    Color.alphaBlend(
                                      colorScheme.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      colors.card,
                                    ),
                                    progress.clamp(0, 1),
                                  )!,
                                  size: metrics.decorationSize,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: metrics.padding,
                  child: Row(
                    spacing: metrics.gap,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DashboardCardHeader(
                              glyph: AppGlyphs.status,
                              title: appLocalizations.status,
                              leading: [
                                DashboardChip(
                                  label: chipLabel,
                                  tone: chipTone,
                                  dot: isStart,
                                ),
                              ],
                            ),
                            SizedBox(height: metrics.ipTop),
                            _ExitRow(
                              info: ipInfo,
                              failed: failed,
                              loading: loading,
                              checking:
                                  phase == ProbePhase.probing || qualityLoading,
                              onRefresh: () => _refresh(ipInfo?.ip),
                              quality: quality,
                              active: isStart,
                              metrics: metrics,
                              large: !density.isDesktop,
                            ),
                            if (density.isDesktop)
                              const Spacer()
                            else
                              const SizedBox(height: 16),
                            _Cells(
                              quality: quality,
                              loading: loading,
                              active: isStart && !suspended,
                              gap: metrics.cellGap,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: metrics.buttonSlot,
                        child: Center(
                          child: _StartToggle(
                            size: metrics.buttonSize,
                            enabled: hasProfile,
                            running: isStart,
                            suspended: suspended,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _OutboundMetrics {
  const _OutboundMetrics({
    required this.padding,
    required this.gap,
    required this.ipTop,
    required this.cellGap,
    required this.badgeSize,
    required this.ip,
    required this.buttonSize,
    required this.buttonSlot,
    required this.decorationSize,
    required this.decorationEnd,
    required this.decorationTop,
  });

  factory _OutboundMetrics.of(DashboardDensity density) => switch (density) {
    DashboardDensity.standard => _OutboundMetrics(
      padding: dashboardCardPadding(density),
      gap: 16,
      ipTop: 10,
      cellGap: 28,
      badgeSize: 48,
      ip: AppTextStyle.title1,
      buttonSize: 104,
      buttonSlot: 120,
      decorationSize: 290,
      decorationEnd: -64,
      decorationTop: -87,
    ),
    DashboardDensity.compact => _OutboundMetrics(
      padding: dashboardCardPadding(density),
      gap: 16,
      ipTop: 8,
      cellGap: 22,
      badgeSize: 40,
      ip: AppTextStyle.title2,
      buttonSize: 84,
      buttonSlot: 100,
      decorationSize: 250,
      decorationEnd: -64,
      decorationTop: -75,
    ),
    DashboardDensity.mobile => const _OutboundMetrics(
      padding: EdgeInsetsDirectional.fromSTEB(20, 18, 16, 18),
      gap: 10,
      ipTop: 12,
      cellGap: 24,
      badgeSize: 48,
      ip: AppTextStyle.title2,
      buttonSize: 88,
      buttonSlot: 88,
      decorationSize: 240,
      decorationEnd: -60,
      decorationTop: -66,
    ),
  };

  final EdgeInsetsGeometry padding;
  final double gap;
  final double ipTop;
  final double cellGap;
  final double badgeSize;
  final AppTextStyle ip;
  final double buttonSize;
  final double buttonSlot;
  final double decorationSize;
  final double decorationEnd;
  final double decorationTop;
}

class _ExitRow extends StatelessWidget {
  const _ExitRow({
    required this.info,
    required this.failed,
    required this.loading,
    required this.checking,
    required this.onRefresh,
    required this.quality,
    required this.active,
    required this.metrics,
    required this.large,
  });

  final IpInfo? info;
  final bool failed;
  final bool loading;
  final bool checking;
  final VoidCallback onRefresh;
  final IpQuality? quality;
  final bool active;
  final _OutboundMetrics metrics;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final style = DashboardText.figure(
      context,
      metrics.ip,
      color: active ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
    ).copyWith(letterSpacing: 0);
    final info = this.info;
    final appLocalizations = context.appLocalizations;
    final Widget ip = info != null
        ? Tooltip(
            message: appLocalizations.details(appLocalizations.outboundIp),
            child: FocusRing(
              shape: AppShape.xs,
              standsOff: true,
              child: PressRegion(
                onTap: () => showIpQualitySheet(context, ip: info.ip),
                shape: AppShape.xs,
                overlay: PressRegion.focusOverlay,
                child: _IpText(ip: info.ip, style: style),
              ),
            ),
          )
        : failed
        ? Text(
            appLocalizations.serviceFailed,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(color: colorScheme.error),
          )
        : SkeletonText(width: 140, style: style);
    return Row(
      spacing: 12,
      children: [
        _CountryBadge(
          countryCode: info?.countryCode,
          size: metrics.badgeSize,
          active: active,
          checking: checking,
          onRefresh: onRefresh,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height:
                    metrics.ip.leading * DashboardDensityScope.scaleOf(context),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ip,
                ),
              ),
              const SizedBox(height: 4),
              if (failed)
                SizedBox(
                  height: _chipHeight(large),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      appLocalizations.tapIconToRetry,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardText.label(context),
                    ),
                  ),
                )
              else
                _IpChips(quality: quality, loading: loading, large: large),
            ],
          ),
        ),
      ],
    );
  }
}

class _IpText extends ConsumerWidget {
  const _IpText({required this.ip, required this.style});

  final String ip;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideIp = ref.watch(
      appSettingProvider.select((state) => state.hideIp),
    );
    return DashboardFitText(hideIp ? _ipMask : ip, style: style);
  }
}

double _chipHeight(bool large) => large ? 28 : 24;

const _chipSkeletonWidths = [48.0, 72.0];

class _IpChips extends StatelessWidget {
  const _IpChips({
    required this.quality,
    required this.loading,
    required this.large,
  });

  final IpQuality? quality;
  final bool loading;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final quality = this.quality;
    final height = _chipHeight(large);
    // Chips that do not fit wrap onto a clipped second line; the details
    // sheet still lists them all.
    return SizedBox(
      height: height,
      child: ClipRect(
        child: Wrap(
          spacing: 6,
          runSpacing: height,
          children: switch (quality) {
            final quality? => [
              DashboardChip(label: quality.type.label(context), large: large),
              DashboardChip(
                label:
                    '${context.appLocalizations.ipQualityShort} ${quality.level.label(context)}',
                tone: switch (quality.level) {
                  IpQualityLevel.good => DashboardChipTone.ok,
                  IpQualityLevel.normal => DashboardChipTone.idle,
                  IpQualityLevel.risky => DashboardChipTone.warn,
                },
                large: large,
              ),
            ],
            null when loading => [
              for (final width in _chipSkeletonWidths)
                SkeletonPill(width: width, height: height),
            ],
            null => [
              DashboardChip(
                label: context.appLocalizations.ipTypeUnknown,
                large: large,
              ),
            ],
          },
        ),
      ),
    );
  }
}

const _spinPeriod = Duration(milliseconds: 1500);

/// The exit's country on a clover that checks the exit again when tapped and
/// turns while it is being checked.
class _CountryBadge extends StatefulWidget {
  const _CountryBadge({
    required this.countryCode,
    required this.size,
    required this.active,
    required this.checking,
    required this.onRefresh,
  });

  final String? countryCode;
  final double size;
  final bool active;
  final bool checking;
  final VoidCallback onRefresh;

  @override
  State<_CountryBadge> createState() => _CountryBadgeState();
}

class _CountryBadgeState extends State<_CountryBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: _spinPeriod,
  );
  var _hovered = false;
  var _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spin();
  }

  @override
  void didUpdateWidget(_CountryBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checking != widget.checking) {
      _spin();
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  void _spin() {
    if (context.disableAnimations) {
      _turns.value = 0;
    } else if (widget.checking) {
      _turns.repeat();
    } else {
      // A clover looks the same every quarter turn, so it stops on the next.
      final rest = (_turns.value * 4).ceil() / 4;
      _turns.animateTo(rest, duration: _spinPeriod * (rest - _turns.value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final foreground = widget.active
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;
    final enabled = !widget.checking;
    final size = widget.size;
    final code = widget.countryCode;
    final tooltip = context.appLocalizations.retry;
    final color = Color.alphaBlend(
      foreground.withValues(alpha: enabled && _hovered ? 0.08 : 0),
      DashboardColors.of(context).tone2,
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: PressRegion(
          onTap: enabled ? widget.onRefresh : null,
          onHover: (value) => setState(() => _hovered = value),
          onFocusChange: (value) => setState(() => _focused = value),
          child: ElasticPress(
            enabled: enabled,
            child: AnimatedBuilder(
              animation: _turns,
              builder: (_, child) => ShapeBadge(
                shape: MaterialShapes.clover4Leaf,
                color: color,
                size: size,
                rotation: _turns.value * 2 * math.pi,
                ring: _focused ? focusRingSide(colorScheme) : null,
                child: child,
              ),
              child: code == null || code.isEmpty
                  ? GlyphIcon(
                      AppGlyphs.proxies,
                      size: size * 0.42,
                      color: foreground,
                    )
                  : Text(
                      code.toUpperCase(),
                      maxLines: 1,
                      style: AppTextStyle.footnote
                          .of(context, emphasized: true)
                          .copyWith(
                            color: foreground,
                            letterSpacing: 0.04 * AppTextStyle.footnote.size,
                          ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cells extends StatelessWidget {
  const _Cells({
    required this.quality,
    required this.loading,
    required this.active,
    required this.gap,
  });

  final IpQuality? quality;
  final bool loading;
  final bool active;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final organization = switch (quality) {
      IpQuality(organization: final name?) when name.isNotEmpty => name,
      IpQuality(asn: final asn?) => 'AS$asn',
      _ => null,
    };
    return Row(
      spacing: gap,
      children: [
        _Cell(
          label: appLocalizations.runTime,
          value: active ? const _RunTimeValue() : const _Placeholder(),
        ),
        Flexible(
          child: _Cell(
            label: appLocalizations.ipOrganization,
            value: organization != null
                ? _CellText(organization)
                : loading
                ? SkeletonText(width: 96, style: _cellStyle(context))
                : const _Placeholder(),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
        const SizedBox(height: 2),
        value,
      ],
    );
  }
}

TextStyle _cellStyle(BuildContext context) =>
    AppTextStyle.subheadline.of(context, emphasized: true).toTabular;

class _CellText extends StatelessWidget {
  const _CellText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _cellStyle(context),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Text('—', maxLines: 1, style: _cellStyle(context));
  }
}

class _RunTimeValue extends ConsumerWidget {
  const _RunTimeValue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CellText(getTimeText(ref.watch(runTimeProvider)));
  }
}

const _morphDuration = Duration(milliseconds: 450);
const _stateDuration = Duration(milliseconds: 150);

final _startMorph = Morph(MaterialShapes.circle, MaterialShapes.cookie9Sided);

Path _morphPath(double progress) => _startMorph.toPath(progress: progress);

double _morphTurn(double progress) => progress * 2 * math.pi / 9;

/// A circle with a play glyph while stopped that grows the cookie-9 of a
/// running tunnel, the way the M3 Expressive loader morphs between shapes.
class _StartToggle extends ConsumerStatefulWidget {
  const _StartToggle({
    required this.size,
    required this.enabled,
    required this.running,
    required this.suspended,
  });

  final double size;
  final bool enabled;
  final bool running;
  final bool suspended;

  @override
  ConsumerState<_StartToggle> createState() => _StartToggleState();
}

class _StartToggleState extends ConsumerState<_StartToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _morphDuration,
    value: widget.running ? 1 : 0,
  );
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );
  var _hovered = false;
  var _pressed = false;
  var _focused = false;

  /// The M3 state layer, painted inside the shape: the card's decoration
  /// covers the button, so ink on the card would never show.
  double get _overlay => !widget.enabled
      ? 0
      : _focused
      ? 0.1
      : _hovered
      ? 0.08
      : 0;

  @override
  void didUpdateWidget(_StartToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running) {
      widget.running ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    ref.read(commonActionProvider.notifier).toggleRunning();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    final glass = LiquidGlassScope.of(context);
    final size = widget.size;
    final enabled = widget.enabled;
    final fill = enabled
        ? colorScheme.primary
        : DashboardColors.of(context).tone2;
    final ink = enabled ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;
    final tooltip = widget.suspended
        ? appLocalizations.suspended
        : widget.running
        ? appLocalizations.stop
        : appLocalizations.start;
    final stateDuration = context.motionDuration(_stateDuration);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: PressRegion(
          onTap: enabled ? _toggle : null,
          onHover: (value) => setState(() => _hovered = value),
          onPressedChanged: (value) => setState(() => _pressed = value),
          onFocusChange: (value) => setState(() => _focused = value),
          child: ElasticPress(
            enabled: enabled,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _overlay),
              duration: stateDuration,
              builder: (_, overlay, child) => AnimatedBuilder(
                animation: _progress,
                builder: (_, child) {
                  final progress = _progress.value;
                  final color = Color.alphaBlend(
                    ink.withValues(alpha: overlay),
                    fill,
                  );
                  return CustomPaint(
                    painter: _MorphPainter(
                      progress: progress,
                      color: glass ? null : color,
                      shadow: enabled
                          ? colorScheme.primary.withValues(alpha: 0.3)
                          : Colors.transparent,
                      ring: _focused
                          ? focusRingSide(colorScheme, standsOff: true)
                          : null,
                    ),
                    child: glass
                        ? LiquidGlass(
                            style: LiquidGlassStyle.tinted(colorScheme, color),
                            clipper: _MorphClipper(progress),
                            pressed: _pressed,
                            child: child,
                          )
                        : child,
                  );
                },
                child: child,
              ),
              child: SizedBox.square(
                dimension: size,
                child: Center(
                  child: widget.suspended
                      ? GlyphIcon(
                          AppGlyphs.wifiOff,
                          size: size * 0.34,
                          color: ink,
                          fill: 1,
                        )
                      : TweenAnimationBuilder<double>(
                          tween: Tween(end: widget.running ? 1 : 0),
                          duration: _morphDuration,
                          curve: Curves.easeOutBack,
                          builder: (_, progress, _) => GlyphIcon(
                            AppGlyphs.playPause(progress),
                            size: size * 0.34,
                            color: ink,
                            fill: 1,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fills the morph, or with no [color] leaves its inside to glass and casts
/// [shadow] only outside it, as one under glass would show through.
class _MorphPainter extends CustomPainter {
  const _MorphPainter({
    required this.progress,
    required this.color,
    required this.shadow,
    required this.ring,
  });

  static const _shadowOffset = Offset(0, 6);
  static const _shadowBlur = 14.0;

  final double progress;
  final Color? color;
  final Color shadow;
  final BorderSide? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _morphPath(progress);
    final color = this.color;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(_morphTurn(progress))
      ..scale(size.width, size.height)
      ..translate(-0.5, -0.5);
    if (shadow.a > 0) {
      canvas.save();
      if (color == null) {
        canvas.clipPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(const Rect.fromLTRB(-1, -1, 2, 2))
            ..addPath(path, Offset.zero),
        );
      }
      canvas
        ..translate(
          _shadowOffset.dx / size.width,
          _shadowOffset.dy / size.height,
        )
        ..drawPath(
          path,
          Paint()
            ..color = shadow
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              _shadowBlur / 2 / size.width,
            ),
        )
        ..restore();
    }
    if (color != null) {
      canvas.drawPath(path, Paint()..color = color);
    }
    if (ring case final ring?) {
      strokeUnitShape(canvas, path, size.width, ring);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MorphPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.shadow != shadow ||
      oldDelegate.ring != ring;
}

class _MorphClipper extends CustomClipper<Path> {
  const _MorphClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    final transform =
        Matrix4.translationValues(size.width / 2, size.height / 2, 0)
          ..rotateZ(_morphTurn(progress))
          ..scaleByDouble(size.width, size.height, 1, 1)
          ..translateByDouble(-0.5, -0.5, 0, 1);
    return _morphPath(progress).transform(transform.storage);
  }

  @override
  bool shouldReclip(_MorphClipper oldClipper) =>
      oldClipper.progress != progress;
}

class _OverviewHero extends ConsumerWidget {
  const _OverviewHero({
    required this.running,
    required this.suspended,
    required this.enabled,
    required this.ip,
    required this.onRefresh,
    required this.label,
    required this.tone,
  });

  final bool running, suspended, enabled;
  final String? ip;
  final VoidCallback onRefresh;
  final String label;
  final DashboardChipTone tone;

  static const _power = Glyph([
    GlyphArc(12, 13, 8, -math.pi / 3, 5 * math.pi / 3),
    GlyphPolyline([GlyphVertex(12, 2), GlyphVertex(12, 12)]),
  ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final scheme = context.colorScheme;
    final active = running && !suspended;
    final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
    final group = !active || mode == Mode.direct
        ? null
        : mode == Mode.global
        ? 'GLOBAL'
        : ref.watch(
            groupsProvider.select(
              (groups) => groups
                  .where((g) => g.hidden == false && g.name != 'GLOBAL')
                  .firstOrNull
                  ?.name,
            ),
          );
    final name = group == null
        ? null
        : ref.watch(
            realSelectedProxyStateProvider(group).select((s) => s.proxyName),
          );
    final latency = group == null
        ? null
        : ref.watch(delayProvider(proxyName: group));
    final title = !running
        ? l.coreStopped
        : suspended
        ? l.suspended
        : mode == Mode.direct
        ? l.direct
        : name ?? l.unknown;
    final detail = active && mode == Mode.direct
        ? l.dashboardDirectModeDescription
        : [
            mode.label,
            ?group,
            if (latency != null && latency > 0) '$latency ms',
          ].join(' · ');
    final hideIp = ref.watch(appSettingProvider.select((s) => s.hideIp));
    final action = running ? l.stop : l.start;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 550;
        final edge = narrow ? 14.0 : 30.0;
        final slot = narrow ? 112.0 : 152.0;
        return Stack(
          children: [
            Positioned.fill(
              child: ClipPath(
                clipper: ShapeBorderClipper(
                  shape: AppShape.all(
                    dashboardCardRadius(DashboardDensityScope.of(context)),
                  ),
                ),
                child: _FiberField(active: active, inset: edge + slot / 2),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: edge),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DashboardCardHeader(
                          title: l.outbound,
                          leading: [
                            DashboardChip(
                              label: label,
                              tone: tone,
                              dot: active,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.title1.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DashboardText.label(context),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          spacing: narrow ? 8 : 26,
                          children: [
                            Flexible(
                              child: _Cell(
                                label: l.outboundIp,
                                value: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Tooltip(
                                        message: ip == null
                                            ? l.retry
                                            : l.details(l.outboundIp),
                                        child: PressRegion(
                                          onTap: !active
                                              ? null
                                              : ip == null
                                              ? onRefresh
                                              : () => showIpQualitySheet(
                                                  context,
                                                  ip: ip!,
                                                ),
                                          child: Text(
                                            !active || ip == null
                                                ? '—'
                                                : hideIp
                                                ? _ipMask
                                                : ip!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: _cellStyle(context),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (active && ip != null)
                                      IconButton(
                                        tooltip: hideIp ? l.show : l.hideIp,
                                        icon: GlyphIcon(
                                          hideIp
                                              ? AppGlyphs.eyeOff
                                              : AppGlyphs.eye,
                                          size: 15,
                                        ),
                                        onPressed: () => ref
                                            .read(appSettingProvider.notifier)
                                            .update(
                                              (s) =>
                                                  s.copyWith(hideIp: !hideIp),
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            Flexible(
                              child: _Cell(
                                label: l.runTime,
                                value: active
                                    ? const _RunTimeValue()
                                    : const _Placeholder(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: slot,
                    child: Center(
                      child: Tooltip(
                        message: action,
                        child: Semantics(
                          button: true,
                          toggled: running,
                          enabled: enabled,
                          label: action,
                          child: FocusRing(
                            shape: AppShape.circle,
                            child: PressSurface(
                              shape: AppShape.circle,
                              fill: active
                                  ? scheme.primary
                                  : DashboardColors.of(context).tone,
                              onPressed: enabled
                                  ? () => ref
                                        .read(commonActionProvider.notifier)
                                        .toggleRunning()
                                  : null,
                              child: SizedBox.square(
                                dimension: 78,
                                child: Center(
                                  child: GlyphIcon(
                                    _power,
                                    size: 32,
                                    color: active
                                        ? scheme.onPrimary
                                        : scheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FiberField extends StatefulWidget {
  const _FiberField({required this.active, required this.inset});
  final bool active;
  final double inset;
  @override
  State<_FiberField> createState() => _FiberFieldState();
}

class _FiberFieldState extends State<_FiberField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3312),
  );

  void _sync() {
    if (widget.active &&
        !context.disableAnimations &&
        TickerMode.valuesOf(context).enabled) {
      if (!_clock.isAnimating) _clock.repeat();
    } else {
      _clock.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_FiberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: widget.active ? 1 : 0,
      duration: context.motionDuration(const Duration(milliseconds: 550)),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _FiberPainter(
            _clock,
            widget.inset,
            Directionality.of(context),
          ),
        ),
      ),
    ),
  );
}

class _FiberPainter extends CustomPainter {
  _FiberPainter(this.clock, this.inset, this.direction) : super(repaint: clock);
  final Animation<double> clock;
  final double inset;
  final TextDirection direction;
  static const _ink = Color(0xff39aaff);
  static const _delays = [.3, 1.7, 3.1, .9, 2.4, 3.9, 1.3, 2.8, 4.2, .6];
  static final _fibers = [
    for (final p in const <List<double>>[
      [210, 14, 380, 4, 560, 12, 710, 46, 794, 74],
      [245, 38, 410, 18, 575, 44, 705, 64, 790, 80],
      [265, 64, 430, 82, 585, 38, 718, 68, 795, 84],
      [250, 92, 415, 112, 575, 72, 715, 86, 795, 90],
      [275, 118, 435, 98, 590, 132, 722, 108, 796, 98],
      [240, 144, 415, 162, 580, 126, 712, 116, 792, 104],
      [205, 168, 395, 178, 585, 156, 720, 128, 796, 108],
      [944, 14, 898, 12, 868, 28, 852, 54, 842, 78],
      [944, 76, 904, 60, 882, 68, 864, 78, 846, 90],
      [944, 160, 902, 174, 872, 150, 854, 124, 842, 102],
    ])
      Path()
        ..moveTo(p[0], p[1])
        ..cubicTo(p[2], p[3], p[4], p[5], p[6], p[7])
        ..cubicTo(2 * p[6] - p[4], 2 * p[7] - p[5], p[8], p[9], 834, 90),
  ];
  static final _metrics = [
    for (final path in _fibers) path.computeMetrics().first,
  ];
  static final _guide = ui.Gradient.linear(
    const Offset(205, 0),
    const Offset(450, 0),
    [_ink.withValues(alpha: 0), _ink.withValues(alpha: .22)],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = clock.value * 3312;
    final center = Offset(size.width - inset, size.height / 2);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..strokeCap = StrokeCap.round;
    canvas.save();
    if (direction == TextDirection.rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    for (var i = 0; i < _fibers.length; i++) {
      canvas.save();
      final scale = i < 7 ? center.dx / 834 : inset / 106;
      canvas.translate(center.dx, center.dy);
      canvas.scale(scale, size.height / 180);
      canvas.translate(-834, -90);
      canvas.drawPath(
        _fibers[i],
        line
          ..color = _ink
          ..shader = _guide,
      );
      line.shader = null;
      final metric = _metrics[i];
      for (var tail = 2; tail >= 0; tail--) {
        final t = ((seconds + _delays[i] - tail * .125) / 4.6) % 1;
        final end = (t * 1.133 - .078) * metric.length;
        if (end <= 0 || end - .042 * metric.length >= metric.length) continue;
        canvas.drawPath(
          metric.extractPath(end - .042 * metric.length, end),
          line
            ..color = _ink.withValues(
              alpha: (1 - tail * .36) * (i < 7 ? (t * 3).clamp(0, 1) : 1),
            ),
        );
      }
      canvas.restore();
    }
    for (final (radius, turn) in [
      (52.0, seconds / 9),
      (45.0, -seconds / 6 + .5),
    ]) {
      final arc = Rect.fromCircle(center: Offset.zero, radius: radius);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(turn * 2 * math.pi);
      line
        ..color = _ink
        ..strokeWidth = 1.5
        ..shader = _arcInk;
      canvas.drawArc(arc, 0, 2.7, false, line);
      canvas.restore();
    }
    final ripple = (seconds % 3.2 / 3.2 / .85).clamp(0.0, 1.0);
    canvas.drawCircle(
      center,
      39 + 19 * Curves.easeOut.transform(ripple),
      line
        ..shader = null
        ..strokeWidth = 1
        ..color = _ink.withValues(alpha: (1 - ripple) * .5),
    );
    canvas.restore();
  }

  static final _arcInk = ui.Gradient.sweep(
    Offset.zero,
    [_ink.withValues(alpha: 0), _ink],
    [0, .43],
  );
  @override
  bool shouldRepaint(_FiberPainter old) =>
      old.clock != clock || old.inset != inset || old.direction != direction;
}
