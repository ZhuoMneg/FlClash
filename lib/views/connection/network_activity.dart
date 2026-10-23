import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/connection/activity_section.dart';
import 'package:fl_clash/views/connection/connections.dart';
import 'package:fl_clash/views/connection/requests.dart';
import 'package:fl_clash/views/dns_queries.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

class NetworkActivityView extends StatefulWidget {
  const NetworkActivityView({super.key});

  @override
  State<NetworkActivityView> createState() => _NetworkActivityViewState();
}

class _NetworkActivityViewState extends State<NetworkActivityView> {
  var _selected = 0;

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
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
              ChoiceChip(
                key: ValueKey('network-activity-tab-$index'),
                label: Text(label),
                selected: _selected == index,
                onSelected: (_) => setState(() => _selected = index),
              ),
          ],
        ),
      ),
      child: IndexedStack(
        index: _selected,
        children: [
          for (final (index, page) in const [
            ConnectionsView(),
            RequestsView(),
            DnsQueriesView(),
          ].indexed)
            PageActivityScope(
              isActive:
                  PageActivityScope.isActiveOf(context) && _selected == index,
              child: TickerMode(enabled: _selected == index, child: page),
            ),
        ],
      ),
    );
  }
}
