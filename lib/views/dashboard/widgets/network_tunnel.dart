import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

class NetworkTunnelTile extends ConsumerStatefulWidget {
  const NetworkTunnelTile({super.key});

  @override
  ConsumerState<NetworkTunnelTile> createState() => _NetworkTunnelTileState();
}

class _NetworkTunnelTileState extends ConsumerState<NetworkTunnelTile>
    with WidgetsBindingObserver, ActivePollingMixin<NetworkTunnelTile> {
  Map<String, dynamic> _status = const {};
  bool _polling = false;

  @override
  Duration get pollInterval => const Duration(seconds: 3);

  @override
  bool get canPoll {
    if (!super.canPoll) return false;
    final settings = ref.read(networkSettingProvider).networkTunnel;
    return settings.enabled &&
        settings.appliesTo(ref.read(currentProfileIdProvider)) &&
        ref.read(coreStatusProvider) == CoreStatus.connected;
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(coreStatusProvider, (_, _) => _invalidateStatus());
    ref.listenManual(currentProfileIdProvider, (_, _) => _invalidateStatus());
    ref.listenManual(
      networkSettingProvider.select((state) => state.networkTunnel),
      (_, _) => _invalidateStatus(),
    );
  }

  void _invalidateStatus() {
    setState(() => _status = const {});
    restartPolling();
  }

  @override
  Future<void> poll(PollGuard isCurrent) async {
    if (_polling) return;
    _polling = true;
    try {
      final status = await ref
          .read(coreHandlerProvider)
          .getNetworkTunnelStatus();
      if (isCurrent()) setState(() => _status = status);
    } catch (_) {
      if (isCurrent()) setState(() => _status = const {});
    } finally {
      _polling = false;
    }
  }

  void _openSettings() => ref
      .read(currentPageLabelProvider.notifier)
      .toPage(PageLabel.networkTunnel);

  void _change(bool enabled) {
    if (!ref.read(networkSettingProvider).networkTunnel.configured) {
      _openSettings();
      return;
    }
    ref
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith.networkTunnel(enabled: enabled));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final density = DashboardDensityScope.of(context);
    final compact = density.isCompact;
    final settings = ref.watch(
      networkSettingProvider.select((state) => state.networkTunnel),
    );
    final active = settings.appliesTo(ref.watch(currentProfileIdProvider));
    final connected = ref.watch(coreStatusProvider) == CoreStatus.connected;
    final lastReply = (_status['lastReply'] as num?) ?? 0;
    final recent =
        lastReply > 0 &&
        DateTime.now().millisecondsSinceEpoch / 1000 - lastReply < 60;
    final receiving =
        _status['running'] == true &&
        recent &&
        ((_status['received'] as num?) ?? 0) > 0;
    final state = !settings.configured
        ? l.tunnelUnconfigured
        : !settings.enabled
        ? l.tunnelDisabled
        : !active
        ? l.tunnelProfileMismatch
        : !connected
        ? l.tunnelCoreStopped
        : (_status['error'] as String? ?? '').isNotEmpty
        ? l.tunnelDirectoryFailed
        : receiving
        ? l.tunnelReceiving
        : l.tunnelWaiting;
    final endpoint = _status['home'] as String?;
    final peer = endpoint?.isNotEmpty == true
        ? '${l.tunnelEndpoint} $endpoint'
        : settings.configured
        ? '${l.tunnelDirectory} ${settings.host}:${settings.port}'
        : '${l.tunnelEndpoint} —';
    final reply = lastReply > 0
        ? DateFormat.Hms('en_US').format(
            DateTime.fromMillisecondsSinceEpoch((lastReply * 1000).round()),
          )
        : '—';
    return DashboardCard(
      padding: EdgeInsets.zero,
      child: DashboardSwitchRow(
        glyph: AppGlyphs.networkTunnel,
        title: l.networkTunnel,
        status: DashboardChip(
          label: state,
          tone: receiving ? DashboardChipTone.ok : DashboardChipTone.idle,
        ),
        subtitle: '$peer · ${l.tunnelLastReply} $reply',
        value: settings.configured && settings.enabled,
        onChanged: _change,
        iconSize: compact ? 36 : 40,
        padding: compact
            ? const EdgeInsets.fromLTRB(10, 0, 12, 0)
            : const EdgeInsets.fromLTRB(12, 0, 16, 0),
        radius: dashboardCardRadius(density),
        color: Colors.transparent,
        onTap: _openSettings,
      ),
    );
  }
}
