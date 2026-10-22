part of '../state.dart';

@riverpod
NavigationItemsState navigationItemsState(Ref ref) {
  final settings = ref.watch(appSettingProvider);
  final openLogs = settings.openLogs;
  final hasProfiles = ref.watch(
    profilesProvider.select((state) => state.isNotEmpty),
  );
  final hasProxies = ref.watch(
    currentGroupsStateProvider.select((state) => state.value.isNotEmpty),
  );
  final isInit = ref.watch(initProvider);
  return NavigationItemsState(
    value: [
      for (final item
          in navigationPort?.getItems(
                openLogs: openLogs,
                hasProxies: !isInit ? hasProfiles : hasProxies,
              ) ??
              <NavigationItem>[])
        if (const {
              PageLabel.connections,
              PageLabel.dns,
              PageLabel.logs,
            }.contains(item.label) &&
            settings.pinnedTools.contains(item.label.name))
          item.copyWith(
            modes: {...item.modes, NavigationItemMode.desktop}.toList(),
          )
        else
          item,
    ],
  );
}

List<NavigationItem> orderedSidebarItems(
  List<NavigationItem> items,
  List<String> order,
) {
  final byName = {for (final item in items) item.label.name: item};
  return [
    for (final name in order.toSet())
      if (name != PageLabel.settings.name && byName.containsKey(name))
        byName.remove(name)!,
    for (final item in byName.values)
      if (item.label != PageLabel.settings) item,
    for (final item in items)
      if (item.label == PageLabel.settings) item,
  ];
}

@riverpod
NavigationItemsState currentNavigationItemsState(Ref ref) {
  final viewWidth = ref.watch(viewWidthProvider);
  final navigationItemsState = ref.watch(navigationItemsStateProvider);
  final navigationItemMode = switch (viewWidth <= maxMobileWidth) {
    true => NavigationItemMode.mobile,
    false => NavigationItemMode.desktop,
  };
  final items = navigationItemsState.value
      .where((element) => element.modes.contains(navigationItemMode))
      .toList();
  return NavigationItemsState(
    value: navigationItemMode == NavigationItemMode.desktop
        ? orderedSidebarItems(items, ref.watch(appSettingProvider).sidebarOrder)
        : items,
  );
}

PageLabel shownPageLabelOf(
  PageLabel pageLabel,
  List<NavigationItem> navigationItems,
) {
  if (navigationItems.isEmpty ||
      navigationItems.any((item) => item.label == pageLabel)) {
    return pageLabel;
  }
  return navigationItems.first.label;
}

@riverpod
PageLabel shownPageLabel(Ref ref) {
  return shownPageLabelOf(
    ref.watch(currentPageLabelProvider),
    ref.watch(currentNavigationItemsStateProvider).value,
  );
}

@riverpod
NavigationState navigationState(Ref ref) {
  final pageLabel = ref.watch(shownPageLabelProvider);
  final navigationItems = ref.watch(currentNavigationItemsStateProvider).value;
  final viewMode = ref.watch(viewModeProvider);
  final locale = ref.watch(appSettingProvider).locale;
  final index = navigationItems.lastIndexWhere(
    (element) => element.label == pageLabel,
  );
  final currentIndex = index == -1 ? 0 : index;
  return NavigationState(
    pageLabel: pageLabel,
    navigationItems: navigationItems,
    viewMode: viewMode,
    locale: locale,
    currentIndex: currentIndex,
  );
}

@riverpod
DashboardState dashboardState(Ref ref) {
  final dashboardWidgets = ref.watch(
    appSettingProvider.select((state) => state.dashboardWidgets),
  );
  return DashboardState(dashboardWidgets: dashboardWidgets);
}

@riverpod
MoreToolsSelectorState moreToolsSelectorState(Ref ref) {
  final viewMode = ref.watch(viewModeProvider);
  final navigationItems = ref
      .watch(
        navigationItemsStateProvider.select((state) {
          return SelectValue(
            state.value.where((element) {
              final isMore =
                  element.modes.contains(NavigationItemMode.more) ||
                  element.modes.contains(NavigationItemMode.moreFull);
              final isDesktop = element.modes.contains(
                NavigationItemMode.desktop,
              );
              if (isMore && !isDesktop) return true;
              if (viewMode != ViewMode.mobile || !isMore) {
                return false;
              }
              return true;
            }).toList(),
          );
        }),
      )
      .value;

  return MoreToolsSelectorState(navigationItems: navigationItems);
}

@riverpod
double overlayTopOffset(Ref ref) {
  final isMobileView = ref.watch(isMobileViewProvider);
  final version = ref.watch(versionProvider);
  ref.watch(viewSizeProvider);
  final showsHeader = showsWindowHeader(
    isDesktop: system.isDesktop,
    isMacOS: system.isMacOS,
    version: version,
    isMobileView: isMobileView,
  );
  return pageToolbarHeight + (showsHeader ? kHeaderHeight : 0);
}
