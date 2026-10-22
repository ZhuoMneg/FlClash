import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/widgets/profile_detail.dart';
import 'package:fl_clash/views/profiles/custom/rules.dart';
import 'package:fl_clash/views/profiles/extend/extend.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'routing_session.dart';

class RoutingView extends ConsumerWidget {
  const RoutingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    if (profile == null) {
      return CommonScaffold(
        title: context.appLocalizations.routing,
        body: Center(
          child: TextButton(
            onPressed: () => ref.read(currentPageLabelProvider.notifier).value =
                PageLabel.profiles,
            child: Text(context.appLocalizations.profiles),
          ),
        ),
      );
    }
    return _RoutingEditor(key: ValueKey(profile.id), profile: profile);
  }
}

class _RoutingEditor extends ConsumerStatefulWidget {
  const _RoutingEditor({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<_RoutingEditor> createState() => _RoutingEditorState();
}

class _RoutingEditorState extends ConsumerState<_RoutingEditor> {
  final _subscriptions = <StreamSubscription<dynamic>>[];
  late final RoutingApplySession _session;

  @override
  void initState() {
    super.initState();
    final profileId = widget.profile.id;
    _session = RoutingApplySession(
      isCurrent: () =>
          mounted && ref.read(currentProfileIdProvider) == profileId,
      apply: () async {
        ref.invalidate(setupStateProvider(profileId));
        return ref.read(setupActionProvider.notifier).applyProfile();
      },
    );
    final rules = widget.profile.type == ProfileType.custom
        ? database.rulesDao.queryProfileRules(profileId)
        : database.rulesDao.queryAddedRules(profileId);
    _watchChanges(rules.watch(), listEquals);
    _watchChanges(
      database.profilesDao.query().watch().map((profiles) {
        final profile = profiles.getProfile(profileId);
        return (
          profile?.type,
          profile?.extendType,
          profile?.scriptId,
          profile?.matchTarget,
          profile?.overrides,
        );
      }),
      (a, b) => a == b,
    );
    if (widget.profile.type != ProfileType.custom) {
      _watchChanges(
        database.scriptsDao.query().watch().map((scripts) {
          final profile = ref.read(profileProvider(profileId));
          return profile?.extendType == ExtendType.script
              ? scripts
                    .where((script) => script.id == profile?.scriptId)
                    .firstOrNull
              : null;
        }),
        (a, b) => a == b,
      );
    }
  }

  void _watchChanges<T>(Stream<T> stream, bool Function(T, T) equals) {
    var initialized = false;
    T? previous;
    _subscriptions.add(
      stream.listen((next) {
        if (initialized && !equals(previous as T, next)) _session.changed();
        previous = next;
        initialized = true;
      }, onError: (Object _) {}),
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final l = context.appLocalizations;
    final type = switch (profile.type) {
      ProfileType.custom => l.custom,
      ProfileType.url => l.remote,
      ProfileType.file => l.local,
    };
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final state = _session.state;
        final status = switch (state) {
          RoutingApplyState.ready => l.routingAutoApply,
          RoutingApplyState.pending => l.routingPending,
          RoutingApplyState.applying => l.routingApplying,
          RoutingApplyState.applied => l.routingApplied,
          RoutingApplyState.failed => l.routingApplyFailed,
        };
        final title = TooltipText(
          text: Text(
            '${l.routing} · ${profile.realLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
        final actions = [
          IconButtonData(
            glyph: AppGlyphs.swap,
            tooltip: l.switchProfile,
            onPressed: () => showProfilesSheet(context),
          ),
          IconButtonData(
            glyph: AppGlyphs.sync,
            tooltip: l.routingApply,
            isLoading: state == RoutingApplyState.applying,
            onPressed: _session.applyNow,
          ),
        ];
        final header = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '$type · $status',
            key: const ValueKey('routing-apply-status'),
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(
                  color: state == RoutingApplyState.failed
                      ? context.colorScheme.error
                      : context.colorScheme.onSurfaceVariant,
                ),
          ),
        );
        return ProfileIdProvider(
          profileId: profile.id,
          child: profile.type == ProfileType.custom
              ? CustomRulesView(
                  profile.id,
                  titleWidget: title,
                  header: header,
                  iconActions: actions,
                )
              : ExtendView(
                  profileId: profile.id,
                  titleWidget: title,
                  header: header,
                  iconActions: actions,
                  applyOnDispose: false,
                ),
        );
      },
    );
  }
}
