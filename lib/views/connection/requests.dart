import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/features/connection/request_filter.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RequestsView extends ConsumerStatefulWidget {
  final ScrollController? scrollController;

  const RequestsView({super.key, this.scrollController});

  @override
  ConsumerState<RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends ConsumerState<RequestsView>
    with RouteMotionHoldMixin<RequestsView> {
  final _listController = TrackerInfoListController();
  late final ScrollController _scrollController;
  var _filter = const RequestFilter();
  var _manualPause = false;
  late final _physics = FollowEndScrollPhysics(
    isFollowing: () => _listController.value.autoScrollToEnd,
  );

  @override
  void initState() {
    super.initState();
    _scrollController =
        widget.scrollController ??
        sheetScrollController(context, initialScrollOffset: double.maxFinite);
    _listController.setTrackerInfos(ref.read(requestsProvider).list);
    ref.listenManual(requestsProvider.select((state) => state.revision), (
      _,
      _,
    ) {
      updateRequestsThrottler();
    });
  }

  @override
  void dispose() {
    _listController.dispose();
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void updateRequestsThrottler() {
    throttler.call(FunctionTag.requests, () {
      if (!mounted) {
        return;
      }
      updateWhenRouteSettled(
        () => _listController.setTrackerInfos(ref.read(requestsProvider).list),
      );
    }, duration: renderThrottleDuration);
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: PageLabel.requests.label,
      onKeywordsUpdate: _listController.updateKeywords,
      body: Builder(
        builder: (context) => Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                context.contentTopPadding,
                16,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  SearchField(onChanged: _listController.search),
                  _buildFilters(),
                ],
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: FloatingBarScope(
                  inset: 0,
                  child: TopInsetScope(inset: 0, child: _buildRequests()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resumeFollowing() {
    _manualPause = false;
    _listController.resumeAutoScrollToEnd(ref.read(requestsProvider).list);
  }

  Future<void> _chooseFilter({required bool process}) async {
    final l = context.appLocalizations;
    final values =
        _listController.value.trackerInfos
            .map(
              (request) => process
                  ? request.metadata.process
                  : request.chains.firstOrNull ?? '',
            )
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final selected = process ? _filter.process : _filter.outbound;
    final value = await showSheet<String>(
      context: context,
      builder: (sheetContext) => SelectionSheet<String>(
        title: process ? l.process : l.outboundExit,
        sections: [
          SelectionSection(items: ['', ...values]),
        ],
        labelBuilder: (value) => value.isEmpty ? l.requestFilterAll : value,
        selectedOf: (_) => selected ?? '',
        onSelected: (value) => Navigator.of(sheetContext).pop(value),
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      _filter = RequestFilter(
        disposition: _filter.disposition,
        process: process ? (value.isEmpty ? null : value) : _filter.process,
        outbound: process ? _filter.outbound : (value.isEmpty ? null : value),
      );
    });
  }

  Widget _buildFilters() {
    final l = context.appLocalizations;
    Widget disposition(RequestDisposition value, String label) => FilterChip(
      label: Text(label),
      selected: _filter.disposition == value,
      onSelected: (selected) => setState(() {
        _filter = RequestFilter(
          disposition: selected ? value : RequestDisposition.any,
          process: _filter.process,
          outbound: _filter.outbound,
        );
      }),
    );
    return ValueListenableBuilder<TrackerInfosState>(
      valueListenable: _listController,
      builder: (context, state, _) => Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          disposition(RequestDisposition.direct, l.direct),
          disposition(RequestDisposition.rejected, l.requestRejected),
          OutlinedButton(
            onPressed: () => _chooseFilter(process: true),
            child: Text(
              '${l.process}: ${_filter.process ?? l.requestFilterAll}',
            ),
          ),
          OutlinedButton(
            onPressed: () => _chooseFilter(process: false),
            child: Text(
              '${l.outboundExit}: ${_filter.outbound ?? l.requestFilterAll}',
            ),
          ),
          if (_filter.isActive)
            TextButton(
              onPressed: () => setState(() => _filter = const RequestFilter()),
              child: Text(l.reset),
            ),
          TextButton(
            key: const ValueKey('requests-follow-toggle'),
            onPressed: () {
              if (state.autoScrollToEnd) {
                _manualPause = true;
                _listController.setAutoScrollToEnd(false);
              } else {
                _resumeFollowing();
              }
            },
            child: Text(
              state.autoScrollToEnd
                  ? l.requestPauseFollow
                  : l.requestResumeFollow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequests() {
    final appLocalizations = context.appLocalizations;
    return ValueListenableBuilder<TrackerInfosState>(
      valueListenable: _listController,
      builder: (context, state, _) {
        final requests = _filter.isActive
            ? state.list.where(_filter.matches).toList()
            : state.list;
        return NullStatusSwitcher(
          isEmpty: requests.isEmpty,
          isSearching: state.isSearching || _filter.isActive,
          nullStatus: NullStatus(
            label: appLocalizations.nullTip(appLocalizations.requests),
            illustration: NullStatusIllustration.requests,
          ),
          child: RecordTableFrame<TrackerInfo>(
            tableId: 'requests',
            items: requests,
            reverse: true,
            columnsOf: (width) =>
                trackerInfoColumns(context, width: width, isLive: false),
            builder: (context, table, requests) => Align(
              alignment: Alignment.topCenter,
              child: FloatingScrollbar(
                controller: _scrollController,
                hintBuilder: (fraction) {
                  final index = (fraction * (requests.length - 1)).round();
                  return requests[index].start.showFull;
                },
                child: ScrollToEndBox(
                  controller: _scrollController,
                  enable: state.autoScrollToEnd,
                  onCancelToEnd: () {
                    _listController.setAutoScrollToEnd(false);
                  },
                  onResumeToEnd: () {
                    if (!_manualPause) _resumeFollowing();
                  },
                  child: TrackerInfoList(
                    reverse: true,
                    shrinkWrap: true,
                    physics: _physics,
                    controller: _scrollController,
                    padding: EdgeInsets.only(
                      top: 0,
                      bottom: 16 + BottomInsetScope.of(context),
                    ),
                    trackerInfos: requests,
                    table: table,
                    detailTitle: appLocalizations.details(
                      appLocalizations.request,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
