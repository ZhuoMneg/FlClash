import 'package:fl_clash/common/app_ports.dart';
import 'package:fl_clash/common/common.dart' show system;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/ui/icons/app_glyphs.dart';
import 'package:fl_clash/views/views.dart';
import 'package:fl_clash/views/routing.dart';
import 'package:fl_clash/views/network_tunnel.dart';
import 'package:fl_clash/views/connection/network_activity.dart';

class Navigation implements NavigationPort {
  static Navigation? _instance;

  @override
  List<NavigationItem> getItems({
    bool openLogs = false,
    bool hasProxies = false,
  }) {
    return [
      NavigationItem(
        glyph: AppGlyphs.dashboard,
        label: PageLabel.dashboard,
        builder: (_) => const DashboardView(),
      ),
      NavigationItem(
        glyph: AppGlyphs.proxies,
        label: PageLabel.proxies,
        builder: (_) => const ProxiesView(),
        modes: hasProxies
            ? [NavigationItemMode.mobile, NavigationItemMode.desktop]
            : [],
      ),
      NavigationItem(
        glyph: AppGlyphs.profiles,
        label: PageLabel.profiles,
        builder: (_) => const ProfilesView(),
      ),
      NavigationItem(
        glyph: AppGlyphs.filter,
        label: PageLabel.routing,
        builder: (_) => const RoutingView(),
        modes: [NavigationItemMode.desktop, NavigationItemMode.moreFull],
      ),
      NavigationItem(
        glyph: AppGlyphs.requests,
        label: PageLabel.requests,
        builder: (_) => const NetworkActivityView(),
        modes: [NavigationItemMode.desktop, NavigationItemMode.moreFull],
      ),
      NavigationItem(
        glyph: AppGlyphs.connections,
        label: PageLabel.connections,
        builder: (_) => const RequestsView(initialFeed: RequestFeed.live),
        modes: [NavigationItemMode.moreFull],
      ),
      NavigationItem(
        glyph: AppGlyphs.dns,
        label: PageLabel.dns,
        builder: (_) => const DnsQueriesView(),
        modes: [NavigationItemMode.moreFull],
      ),
      NavigationItem(
        glyph: AppGlyphs.resources,
        label: PageLabel.resources,
        builder: (_) => const ResourcesView(),
        modes: [NavigationItemMode.more],
      ),
      NavigationItem(
        glyph: AppGlyphs.logs,
        label: PageLabel.logs,
        builder: (_) => const LogsView(),
        modes: openLogs ? [NavigationItemMode.more] : [],
      ),
      NavigationItem(
        glyph: AppGlyphs.tools,
        label: PageLabel.tools,
        builder: (_) => const ToolsView(),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      if (system.isWindows)
        NavigationItem(
          glyph: AppGlyphs.connections,
          label: PageLabel.networkTunnel,
          builder: (_) => const NetworkTunnelView(),
          modes: [NavigationItemMode.desktop],
        ),
      NavigationItem(
        glyph: AppGlyphs.settings,
        label: PageLabel.settings,
        builder: (_) => const ToolsView(settingsOnly: true),
        modes: [NavigationItemMode.desktop, NavigationItemMode.moreFull],
      ),
    ];
  }

  Navigation._internal();

  factory Navigation() {
    _instance ??= Navigation._internal();
    return _instance!;
  }
}

final navigation = Navigation();
