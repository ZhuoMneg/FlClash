import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/connection/activity_section.dart';

import 'package:fl_clash/views/connection/requests.dart';
import 'package:fl_clash/views/dns_queries.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/providers/providers.dart';

class NetworkActivityView extends ConsumerStatefulWidget {
  const NetworkActivityView({super.key});

  @override
  ConsumerState<NetworkActivityView> createState() =>
      _NetworkActivityViewState();
}

class _NetworkActivityViewState extends ConsumerState<NetworkActivityView> {
  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final selected = ref
        .watch(appSettingProvider.select((s) => s.networkActivityTab))
        .clamp(0, 2);
    return NetworkActivitySection(
      tabs: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, label) in [
              l.liveConnections,
              l.realtimeRequests,
              l.dnsQueries,
            ].indexed)
              Chip(
                key: ValueKey('network-activity-tab-$index'),
                label: label,
                selected: selected == index,
                onPressed: () => ref
                    .read(appSettingProvider.notifier)
                    .update((s) => s.copyWith(networkActivityTab: index)),
              ),
          ],
        ),
      ),
      child: IndexedStack(
        index: selected,
        children: [
          for (final (index, page) in const [
            RequestsView(initialFeed: RequestFeed.live),
            RequestsView(initialFeed: RequestFeed.recent),
            DnsQueriesView(),
          ].indexed)
            PageActivityScope(
              isActive:
                  PageActivityScope.isActiveOf(context) && selected == index,
              child: TickerMode(enabled: selected == index, child: page),
            ),
        ],
      ),
    );
  }
}
