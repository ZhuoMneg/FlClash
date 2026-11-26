import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/system_dns.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/mitm.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/widgets/icon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppStateManager extends ConsumerStatefulWidget {
  final Widget child;

  const AppStateManager({super.key, required this.child});

  @override
  ConsumerState<AppStateManager> createState() => _AppStateManagerState();
}

class _AppStateManagerState extends ConsumerState<AppStateManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A desktop build started to the tray mounts while hidden, and a paused
    // render never runs a post-frame callback.
    scheduleMicrotask(() {
      if (mounted) {
        _updateVisible(WidgetsBinding.instance.lifecycleState);
      }
    });
    ref.listenManual(configProvider, (prev, next) {
      if (prev != next) {
        ref.read(storeActionProvider.notifier).savePreferencesDebounce();
      }
    });
    ref.listenManual(groupsProvider, (prev, next) {
      if (prev != next) {
        unawaited(precacheTargetIcons(next.map((group) => group.icon)));
      }
    }, fireImmediately: true);
    ref.listenManual(iconSetsProvider, (_, next) {
      if (next.value case final iconSets?) {
        unawaited(
          precacheTargetIcons(iconSets.map((iconSet) => iconSet.cover)),
        );
      }
    }, fireImmediately: true);
    ref.listenManual(needUpdateGroupsProvider, (prev, next) {
      if (prev != next) {
        ref.read(proxiesActionProvider.notifier).updateGroupsDebounce();
      }
    });
    ref.listenManual(suspendProvider, (prev, next) {
      if (prev != next) {
        ref.read(setupActionProvider.notifier).syncSuspend();
      }
    });
    if (system.isMacOS && !safeModeBuild) {
      unawaited(restoreLegacySystemDns());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _updateVisible(AppLifecycleState? state) {
    ref.read(appVisibleProvider.notifier).shown = switch (state) {
      null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => false,
    };
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    _updateVisible(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(locationPermissionsProvider.notifier).refresh());
      // A certificate removed meanwhile stops decryption before the next start.
      if (rsFeature && ref.read(patchClashConfigProvider).mitm.enable) {
        unawaited(ref.read(mitmTrustStateProvider.notifier).refresh());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref.read(routeTrackerProvider.notifier).markResumed();
      });
    }
  }

  @override
  void didChangePlatformBrightness() {
    ref.read(themeActionProvider.notifier).updateBrightness();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class AppEnvManager extends ConsumerWidget {
  final Widget child;

  const AppEnvManager({super.key, required this.child});

  String? _bannerMessage({required bool safeMode}) {
    if (safeMode) {
      return 'SAFE MODE';
    }
    if (!globalState.isPre) {
      return null;
    }
    return kDebugMode ? 'DEBUG' : globalState.appEnv.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = _bannerMessage(safeMode: ref.watch(safeModeProvider));
    if (message == null) {
      return child;
    }
    return Banner(
      message: message,
      location: BannerLocation.topEnd,
      child: child,
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.items,
    required this.currentIndex,
    required this.viewMode,
    required this.onSelected,
  });

  final List<NavigationItem> items;
  final int currentIndex;
  final ViewMode viewMode;
  final void Function(int index) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canExpand = canExpandSidebar(viewMode);
    final sidebarExpanded = ref.watch(
      appSettingProvider.select((state) => state.sidebarExpanded),
    );
    final version = ref.watch(versionProvider);
    return NavigationSidebar(
      destinations: [
        for (final item in items)
          SidebarDestination(glyph: item.glyph, label: item.label.label),
      ],
      selectedIndex: currentIndex,
      expanded: canExpand && sidebarExpanded,
      onSelected: onSelected,
      onToggle: canExpand
          ? () {
              ref
                  .read(appSettingProvider.notifier)
                  .update(
                    (state) =>
                        state.copyWith(sidebarExpanded: !state.sidebarExpanded),
                  );
            }
          : null,
      windowControls: windowControlsOverSidebar(
        isMacOS: system.isMacOS,
        version: version,
      ),
    );
  }
}

class AppSidebarContainer extends ConsumerWidget {
  static const _dockPanelCorner = 32.0;
  static const _dockPanelInset = 18.0;
  final Widget child;

  const AppSidebarContainer({super.key, required this.child});

  void _updateSideBarWidth(WidgetRef ref, double contentWidth) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sideWidthProvider.notifier).value =
          ref.read(viewSizeProvider.select((state) => state.width)) -
          contentWidth;
    });
  }

  void _handleToPage(WidgetRef ref, PageLabel pageLabel) {
    final focusNode = FocusManager.instance.primaryFocus;
    final focusContext = focusNode?.context;
    final preserveNavigationFocus =
        focusContext?.findAncestorWidgetOfExactType<NavigationSidebar>() !=
        null;
    ref.read(currentPageLabelProvider.notifier).toPage(pageLabel);
    if (!preserveNavigationFocus || focusNode == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (focusNode.context != null && focusNode.canRequestFocus) {
        focusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigationState = ref.watch(navigationStateProvider);
    final navigationItems = navigationState.navigationItems;
    final viewMode = navigationState.viewMode;
    final currentIndex = navigationState.currentIndex;
    final backdropOpacity = ref.watch(windowBlurProvider);
    final page = SurfaceLevel.page.colorOf(context.colorScheme);
    final chrome = context.colorScheme.appChromeSurface;
    final dockShape = AppShape.all(
      _dockPanelCorner,
    ).copyWith(side: context.colorScheme.cardEdge);
    final horizontalMargin =
        (MediaQuery.sizeOf(context).width - maxMobileWidth).clamp(
          0.0,
          _dockPanelInset * 2,
        ) /
        2;
    void onSelected(int index) {
      _handleToPage(ref, navigationItems[index].label);
    }

    final hasSidebar = viewMode != ViewMode.mobile;
    final isLtr = Directionality.of(context) == TextDirection.ltr;
    return Container(
      color: backdropOpacity != null ? Colors.transparent : page,
      child: Row(
        children: [
          AnimatedVisibility.sidebar(
            visible: hasSidebar,
            child: _SidebarBackdropCutout(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalMargin,
                vertical: 14,
              ),
              shape: dockShape,
              pageColor: backdropOpacity != null ? page : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 610),
                child: Surface(
                  color: backdropOpacity != null
                      ? chrome.withValues(alpha: backdropOpacity)
                      : chrome,
                  shape: dockShape,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: MediaQuery.removePadding(
                      context: context,
                      removeLeft: !isLtr,
                      removeRight: isLtr,
                      child: _Sidebar(
                        items: navigationItems,
                        currentIndex: currentIndex,
                        viewMode: viewMode,
                        onSelected: onSelected,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: ClipRect(
              child: LayoutBuilder(
                builder: (_, constraints) {
                  _updateSideBarWidth(ref, constraints.maxWidth);
                  return MediaQuery.removePadding(
                    context: context,
                    removeLeft: hasSidebar && isLtr,
                    removeRight: hasSidebar && !isLtr,
                    child: child,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarBackdropCutout extends SingleChildRenderObjectWidget {
  const _SidebarBackdropCutout({
    required this.padding,
    required this.shape,
    required this.pageColor,
    required super.child,
  });

  final EdgeInsets padding;
  final RoundedSuperellipseBorder shape;
  final Color? pageColor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSidebarBackdropCutout(this, Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSidebarBackdropCutout renderObject,
  ) {
    renderObject
      ..configuration = this
      ..textDirection = Directionality.of(context);
  }
}

class _RenderSidebarBackdropCutout extends RenderAligningShiftedBox {
  _RenderSidebarBackdropCutout(this._configuration, TextDirection textDirection)
    : super(
        alignment: AlignmentDirectional.topStart,
        textDirection: textDirection,
      );

  _SidebarBackdropCutout _configuration;

  set configuration(_SidebarBackdropCutout value) {
    final previous = _configuration;
    _configuration = value;
    if (previous.padding != value.padding) {
      markNeedsLayout();
    }
    if (previous.shape != value.shape ||
        previous.pageColor != value.pageColor) {
      markNeedsPaint();
    }
  }

  Size _sizeForChild(BoxConstraints constraints, Size childSize) {
    final padding = _configuration.padding;
    return constraints.constrain(
      Size(
        childSize.width + padding.horizontal,
        constraints.hasBoundedHeight
            ? constraints.maxHeight
            : childSize.height + padding.vertical,
      ),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeForChild(
    constraints,
    child?.getDryLayout(constraints.deflate(_configuration.padding).loosen()) ??
        Size.zero,
  );

  @override
  void performLayout() {
    final padding = _configuration.padding;
    final child = this.child;
    child?.layout(constraints.deflate(padding).loosen(), parentUsesSize: true);
    size = _sizeForChild(constraints, child?.size ?? Size.zero);
    if (child == null) {
      return;
    }
    final parentData = child.parentData! as BoxParentData;
    parentData.offset =
        Offset(padding.left, padding.top) +
        resolvedAlignment.alongOffset(
          Offset(
            size.width - padding.horizontal - child.size.width,
            size.height - padding.vertical - child.size.height,
          ),
        );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final pageColor = _configuration.pageColor;
    if (child != null && pageColor != null) {
      final parentData = child.parentData! as BoxParentData;
      final dockRect = (offset + parentData.offset) & child.size;
      final mask = Path.combine(
        PathOperation.difference,
        Path()..addRect(offset & size),
        _configuration.shape.getOuterPath(
          dockRect,
          textDirection: textDirection,
        ),
      );
      context.canvas.drawPath(mask, Paint()..color = pageColor);
    }
    super.paint(context, offset);
  }
}
