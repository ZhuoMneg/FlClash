import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';
import 'connections_table.dart';

class RecentRequestsCard extends ConsumerStatefulWidget {
  const RecentRequestsCard({super.key});

  @override
  ConsumerState<RecentRequestsCard> createState() => _RecentRequestsCardState();
}

class _RecentRequestsCardState extends ConsumerState<RecentRequestsCard>
    with RouteMotionHoldMixin<RecentRequestsCard> {
  List<TrackerInfo> _requests = const [];
  Timer? _snapshot;

  @override
  void initState() {
    super.initState();
    _takeSnapshot();
    ref.listenManual(
      requestsProvider.select((state) => state.revision),
      (_, _) => _scheduleSnapshot(),
    );
  }

  void _takeSnapshot() {
    _requests = ref.read(requestsProvider).list.reversed.take(3).toList();
  }

  void _scheduleSnapshot() {
    _snapshot ??= Timer(renderThrottleDuration, () {
      _snapshot = null;
      if (mounted) updateWhenRouteSettled(() => setState(_takeSnapshot));
    });
  }

  @override
  void dispose() {
    _snapshot?.cancel();
    super.dispose();
  }

  void _openRequests() {
    if (DashboardDensityScope.of(context).isDesktop) {
      ref.read(currentPageLabelProvider.notifier).toPage(PageLabel.requests);
    } else {
      openDashboardFeed(context, DashboardFeed.requests);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = !DashboardDensityScope.of(context).isDesktop;
    final scale = DashboardDensityScope.scaleOf(context);
    final localizations = context.appLocalizations;
    final content = _requests.isEmpty
        ? Center(
            child: Text(
              localizations.nullTip(localizations.requests),
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          )
        : Column(
            mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
            children: [
              for (final request in _requests)
                if (mobile)
                  SizedBox(height: 44 * scale, child: _RequestRow(request))
                else
                  Expanded(child: _RequestRow(request)),
            ],
          );
    return DashboardCard(
      semanticLabel: localizations.recentRequests,
      onTap: _openRequests,
      child: Column(
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.requests,
            title: localizations.recentRequests,
            chevron: true,
          ),
          const SizedBox(height: 12),
          if (mobile) content else Expanded(child: content),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow(this.request);

  final TrackerInfo request;

  @override
  Widget build(BuildContext context) {
    final host = request.metadata.host;
    final target = host.isEmpty ? request.title : host;
    final exit = request.chains.firstOrNull ?? '—';
    return Tooltip(
      message: request.title,
      child: InkWell(
        customBorder: AppShape.all(DashboardCorner.block),
        onTap: () => showTrackerInfoDetail(
          context,
          request,
          context.appLocalizations.details(context.appLocalizations.request),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  target,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote.of(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Text(
                  exit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
