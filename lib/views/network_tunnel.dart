import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/network_tunnel.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
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
    final colors = context.colorScheme;
    final caption = AppTextStyle.footnote
        .of(context)
        .copyWith(color: colors.onSurfaceVariant);
    Widget panel(List<Widget> children) => DecoratedBox(
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(colors),
        shape: AppShape.lg.copyWith(side: colors.cardEdge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: children,
        ),
      ),
    );
    Widget heading(Glyph glyph, String label) => Row(
      spacing: 8,
      children: [
        GlyphIcon(glyph, size: 19, color: colors.primary),
        Expanded(child: Text(label, style: AppTextStyle.headline.of(context))),
      ],
    );
    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        children: [
          Text(label, style: caption),
          Text(
            value,
            style: AppTextStyle.subheadline.of(context, emphasized: true),
          ),
        ],
      ),
    );
    final desktop =
        !ViewScope.isMobileOf(context) &&
        !ScaffoldSurface.of(context).isModal &&
        ModalRoute.of(context)?.impliesAppBarDismissal != true;
    final summary = panel([
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          if (desktop)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  'WireGuard ${l.networkTunnel}',
                  style: AppTextStyle.headline.of(context),
                ),
                DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: AppShape.full,
                    color: colors.primary.withValues(alpha: .10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      state,
                      style: caption.copyWith(color: colors.primary),
                    ),
                  ),
                ),
              ],
            )
          else
            Text(state, style: AppTextStyle.headline.of(context)),
          Wrap(
            spacing: 6,
            children: [
              if (running)
                TextButton(onPressed: _refresh, child: Text(l.tunnelRefresh)),
              FilledButton(
                onPressed: _importing ? null : _import,
                child: Text(l.tunnelImport),
              ),
            ],
          ),
        ],
      ),
      if (settings.configured)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            SizedBox(
              width: 170,
              child: ListItem.toggle(
                padding: EdgeInsets.zero,
                title: const Text('WireGuard'),
                value: settings.enabled,
                onChanged: (value) =>
                    _update((v) => v.copyWith(enabled: value)),
              ),
            ),
            SizedBox(
              width: 216,
              child: ListItem.toggle(
                padding: EdgeInsets.zero,
                title: Text(l.tunnelExtension),
                value: settings.extension,
                onChanged: (value) =>
                    _update((v) => v.copyWith(extension: value)),
              ),
            ),
            TextButton(
              onPressed: () =>
                  _update((v) => v.copyWith(enabled: false, extension: false)),
              child: Text(l.tunnelDisableAll),
            ),
          ],
        ),
      if (_message != null) Text(_message!),
      Text(l.tunnelImportHelp, style: caption),
      if (settings.configured) Text(l.tunnelRoutingHelp, style: caption),
    ]);
    final status = panel([
      heading(AppGlyphs.networkTunnel, l.tunnelStatus),
      if (running) ...[
        fact(l.tunnelEndpoint, '${_status['home'] ?? '—'}'),
        if (_status['physical'] case final String nic when nic.isNotEmpty)
          fact(l.interfaceName, nic),
        if (lastReply > 0)
          fact(
            l.tunnelLastReply,
            DateTime.fromMillisecondsSinceEpoch(lastReply * 1000).showFull,
          ),
        fact(
          l.tunnelTraffic,
          '${l.upload} ${_status['sent'] ?? 0} B · ${l.download} $received B',
        ),
        fact(
          l.tunnelDirectory,
          error.isNotEmpty
              ? l.tunnelDirectoryFailed
              : (_status['lastQuery'] as num? ?? 0) > 0
              ? l.tunnelDirectoryReady
              : l.tunnelWaiting,
        ),
      ],
      Text(l.tunnelStatusHelp, style: caption),
    ]);
    final directories = panel([
      heading(AppGlyphs.link, l.tunnelDirectory),
      if (settings.configured) ...[
        fact(l.tunnelPrimaryDirectory, '${settings.host}:${settings.port}'),
        for (final (i, backup) in settings.fallbacks.indexed)
          fact(l.tunnelBackupDirectory(i + 1), '${backup.host}:${backup.port}'),
      ] else
        const Text('—'),
      const Divider(height: 1),
      fact(
        l.tunnelFailoverPolicy,
        settings.fallbacks.isEmpty
            ? l.tunnelNoFallback
            : l.tunnelFailoverInOrder,
      ),
    ]);
    final body = LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          desktop ? 16 : context.sectionsTopPadding,
          16,
          16 + context.bottomInset,
        ),
        children: [
          summary,
          const SizedBox(height: 14),
          if (constraints.maxWidth >= 700)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 14,
              children: [
                Expanded(flex: 43, child: status),
                Expanded(flex: 57, child: directories),
              ],
            )
          else ...[
            status,
            const SizedBox(height: 14),
            directories,
          ],
        ],
      ),
    );
    return desktop ? body : BaseScaffold(title: l.networkTunnel, body: body);
  }
}
