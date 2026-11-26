import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/network_tunnel.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

class NetworkTunnelView extends ConsumerStatefulWidget {
  const NetworkTunnelView({super.key});

  @override
  ConsumerState<NetworkTunnelView> createState() => _NetworkTunnelViewState();
}

class _NetworkTunnelViewState extends ConsumerState<NetworkTunnelView> {
  Timer? _timer;
  Map<String, dynamic> _status = const {};
  int _statusGeneration = 0;
  int? _pollingGeneration;
  bool _importing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    ref.listenManual(coreStatusProvider, (_, _) => _invalidateStatus());
    ref.listenManual(
      networkSettingProvider.select((value) => value.networkTunnel),
      (_, _) => _invalidateStatus(),
    );
    ref.listenManual(currentProfileIdProvider, (_, _) => _invalidateStatus());
    unawaited(_poll());
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_poll()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _invalidateStatus() {
    if (!mounted) return;
    _statusGeneration++;
    setState(() => _status = const {});
    unawaited(_poll());
  }

  Future<void> _poll() async {
    final generation = _statusGeneration;
    if (!mounted ||
        _pollingGeneration == generation ||
        ref.read(coreStatusProvider) != CoreStatus.connected) {
      return;
    }
    _pollingGeneration = generation;
    try {
      final value = await ref
          .read(coreHandlerProvider)
          .getNetworkTunnelStatus();
      if (mounted && generation == _statusGeneration) {
        setState(() => _status = value);
      }
    } catch (_) {
      if (mounted && generation == _statusGeneration) {
        setState(() => _status = const {});
      }
    } finally {
      if (_pollingGeneration == generation) _pollingGeneration = null;
    }
  }

  void _update(NetworkTunnelSettings Function(NetworkTunnelSettings) update) {
    ref
        .read(networkSettingProvider.notifier)
        .update(
          (state) => state.copyWith(networkTunnel: update(state.networkTunnel)),
        );
  }

  Future<void> _import() async {
    final l = context.appLocalizations;
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) {
      setState(() => _message = l.tunnelSelectProfile);
      return;
    }
    setState(() {
      _importing = true;
      _message = null;
    });
    try {
      final file = await picker.pickerFile();
      if (file == null) return;
      final size = await file.length();
      if (size == null || size == 0 || size > 65536) {
        throw const FormatException();
      }
      final bytes = await file.readBytes();
      if (bytes.length > 65536) throw const FormatException();
      final settings = parseNetworkTunnelImport(utf8.decode(bytes), profileId);
      if (!mounted) return;
      if (ref.read(currentProfileIdProvider) != profileId) {
        setState(() => _message = l.tunnelSelectProfile);
        return;
      }
      _update((_) => settings);
      setState(() => _message = l.tunnelImportDone);
    } catch (_) {
      if (mounted) setState(() => _message = l.tunnelImportFailed);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _refresh() async {
    final generation = _statusGeneration;
    try {
      await ref.read(coreHandlerProvider).refreshNetworkTunnel();
      if (mounted && generation == _statusGeneration) await _poll();
    } catch (_) {
      if (mounted && generation == _statusGeneration) {
        setState(() => _status = const {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final settings = ref.watch(
      networkSettingProvider.select((v) => v.networkTunnel),
    );
    final profileId = ref.watch(currentProfileIdProvider);
    final connected = ref.watch(coreStatusProvider) == CoreStatus.connected;
    final active = settings.appliesTo(profileId);
    final running =
        connected && active && settings.enabled && _status['running'] == true;
    final received = (_status['received'] as num?)?.toInt() ?? 0;
    final lastReply = (_status['lastReply'] as num?)?.toInt() ?? 0;
    final recent =
        lastReply > 0 &&
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - lastReply < 60;
    final error = _status['error'] as String? ?? '';
    final state = !settings.configured
        ? l.tunnelUnconfigured
        : !active
        ? l.tunnelProfileMismatch
        : !connected
        ? l.tunnelCoreStopped
        : !settings.enabled
        ? (settings.extension ? l.tunnelDependencyOff : l.tunnelDisabled)
        : !running
        ? l.tunnelWaiting
        : recent && received > 0
        ? l.tunnelReceiving
        : l.tunnelWaiting;
    return BaseScaffold(
      title: l.networkTunnel,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: [
          generateSection(
            items: [
              ListItem(
                title: Text(l.tunnelImport),
                onTap: _importing ? null : _import,
              ),
              if (_message != null) ListItem(title: Text(_message!)),
            ],
            footer: l.tunnelImportHelp,
          ),
          if (settings.configured)
            generateSection(
              items: [
                ConfigToggleItem(
                  title: (_) => 'WireGuard',
                  selector: networkSettingProvider.select(
                    (v) => v.networkTunnel.enabled,
                  ),
                  onChanged: (_, value) =>
                      _update((v) => v.copyWith(enabled: value)),
                ),
                ConfigToggleItem(
                  title: (l) => l.tunnelExtension,
                  selector: networkSettingProvider.select(
                    (v) => v.networkTunnel.extension,
                  ),
                  onChanged: (_, value) =>
                      _update((v) => v.copyWith(extension: value)),
                ),
                ListItem(
                  title: Text(l.tunnelDisableAll),
                  onTap: () => _update(
                    (v) => v.copyWith(enabled: false, extension: false),
                  ),
                ),
              ],
              footer: l.tunnelRoutingHelp,
            ),
          generateSection(
            title: l.tunnelStatus,
            items: [
              ListItem(title: Text(state)),
              if (running) ...[
                ListItem(
                  title: Text(l.tunnelEndpoint),
                  subtitle: Text('${_status['home'] ?? '—'}'),
                ),
                ListItem(
                  title: Text(l.tunnelTraffic),
                  subtitle: Text('↑ ${_status['sent'] ?? 0} B   ↓ $received B'),
                ),
                ListItem(
                  title: Text(l.tunnelDirectory),
                  subtitle: Text(
                    error.isNotEmpty
                        ? l.tunnelDirectoryFailed
                        : (_status['lastQuery'] as num? ?? 0) > 0
                        ? l.tunnelDirectoryReady
                        : l.tunnelWaiting,
                  ),
                ),
                ListItem(title: Text(l.tunnelRefresh), onTap: _refresh),
              ],
            ],
            footer: l.tunnelStatusHelp,
          ),
        ],
      ),
    );
  }
}
