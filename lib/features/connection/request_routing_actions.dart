import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

String? requestDomain(TrackerInfo request) {
  final host = request.metadata.host.trim().toLowerCase().replaceFirst(
    RegExp(r'\.$'),
    '',
  );
  if (host.isEmpty ||
      InternetAddress.tryParse(host) != null ||
      RegExp(r'[\s/:,?#]').hasMatch(host)) {
    return null;
  }
  return host;
}

enum RequestRuleSaveResult { applied, inactive, failed, duplicate }

Future<RequestRuleSaveResult> saveRequestRule(
  WidgetRef ref, {
  required int profileId,
  required Rule rule,
}) async {
  final container = ProviderScope.containerOf(ref.context, listen: false);
  final profile = container.read(profileProvider(profileId));
  if (container.read(currentProfileIdProvider) != profileId ||
      profile == null ||
      (profile.type != ProfileType.custom &&
          profile.extendType != ExtendType.standard)) {
    return RequestRuleSaveResult.inactive;
  }
  final rules = await database.rulesDao.queryProfileRules(profileId).get();
  if (rules.any(
    (existing) =>
        existing.ruleAction == rule.ruleAction &&
        existing.content == rule.content &&
        existing.ruleTarget == rule.ruleTarget,
  )) {
    return RequestRuleSaveResult.duplicate;
  }
  bool canApply() {
    final current = container.read(currentProfileProvider);
    return current?.id == profileId &&
        (current?.type == ProfileType.custom ||
            current?.extendType == ExtendType.standard);
  }

  if (!canApply()) {
    return RequestRuleSaveResult.inactive;
  }
  final ordered = rule.autoOrder(rule, null, rules.firstOrNull?.order);
  await database.rulesDao.putRule(ordered, profileId: profileId);
  if (!canApply()) {
    return RequestRuleSaveResult.inactive;
  }
  container.invalidate(setupStateProvider(profileId));
  final applied = await container
      .read(setupActionProvider.notifier)
      .applyProfile();
  return applied ? RequestRuleSaveResult.applied : RequestRuleSaveResult.failed;
}

class RequestRoutingActions extends ConsumerStatefulWidget {
  const RequestRoutingActions({super.key, required this.request});

  final TrackerInfo request;

  @override
  ConsumerState<RequestRoutingActions> createState() =>
      _RequestRoutingActionsState();
}

class _RequestRoutingActionsState extends ConsumerState<RequestRoutingActions> {
  var _saving = false;
  var _checking = false;
  String? _error;
  String? _message;
  ProbeResult? _probe;

  Future<void> _createRule() async {
    final l = context.appLocalizations;
    final profile = ref.read(currentProfileProvider);
    final domain = requestDomain(widget.request);
    if (profile == null || domain == null) return;
    if (profile.type != ProfileType.custom &&
        profile.extendType != ExtendType.standard) {
      setState(() => _error = l.requestRuleNeedsStandard);
      return;
    }
    final targets = <String>{
      RuleTarget.DIRECT.value,
      RuleTarget.REJECT.value,
      for (final group in ref.read(groupsProvider))
        if (group.name != GroupName.GLOBAL.name) group.name,
    }.toList();
    final rule = await showFormSheet<Rule>(
      context: context,
      builder: (_) => _RequestRuleForm(
        domain: domain,
        profile: profile.realLabel,
        targets: targets,
      ),
    );
    if (rule == null || !mounted) return;
    if (ref.read(currentProfileIdProvider) != profile.id) {
      setState(() => _error = l.requestProfileChanged);
      return;
    }
    final confirmed = await dialogs.showMessage(
      title: l.addRule,
      message: TextSpan(
        text: l.requestRuleConfirm(profile.realLabel, rule.rawValue),
      ),
      confirmText: l.confirm,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await saveRequestRule(
        ref,
        profileId: profile.id,
        rule: rule,
      );
      if (!mounted) return;
      setState(() {
        switch (result) {
          case RequestRuleSaveResult.applied:
            _message = l.requestRuleApplied;
          case RequestRuleSaveResult.duplicate:
            _message = l.requestRuleDuplicate;
          case RequestRuleSaveResult.inactive:
            _error = l.requestProfileChanged;
          case RequestRuleSaveResult.failed:
            _error = l.requestRuleApplyFailed;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = userFacingErrorMessage(error, l));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _checkRoute() async {
    final l = context.appLocalizations;
    final domain = requestDomain(widget.request);
    if (domain == null) return;
    final url = Uri(scheme: 'https', host: domain).toString();
    final confirmed = await dialogs.showMessage(
      title: l.requestCheckRoute,
      message: TextSpan(text: l.requestCheckRouteConfirm(url)),
      confirmText: l.confirm,
    );
    if (confirmed != true || !mounted) return;
    final profileId = ref.read(currentProfileIdProvider);
    final route = ref.read(routeTrackerProvider);
    setState(() {
      _checking = true;
      _error = null;
      _probe = null;
    });
    try {
      final result = await ref
          .read(coreHandlerProvider)
          .probe(ProbeParams(url: url, timeout: 8000, maxBody: 0));
      if (!mounted) return;
      if (profileId != ref.read(currentProfileIdProvider) ||
          route != ref.read(routeTrackerProvider)) {
        setState(() => _error = l.requestProfileChanged);
      } else if (result == null || result.error?.isNotEmpty == true) {
        setState(() => _error = l.requestRouteCheckFailed);
      } else {
        setState(() => _probe = result);
      }
    } catch (error) {
      if (mounted) setState(() => _error = userFacingErrorMessage(error, l));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (requestDomain(widget.request) == null) return const SizedBox.shrink();
    final l = context.appLocalizations;
    final hasProfile = ref.watch(currentProfileProvider) != null;
    final result = _probe;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        generateSection(
          title: l.routing,
          items: [
            ListItem(
              title: Text(l.requestCreateRule),
              onTap: !hasProfile || _saving ? null : _createRule,
              trailing: _saving ? const CommonCircleLoading(size: 18) : null,
            ),
            ListItem(
              title: Text(l.requestCheckRoute),
              onTap: _checking ? null : _checkRoute,
              trailing: _checking ? const CommonCircleLoading(size: 18) : null,
            ),
          ],
        ),
        ErrorBanner(message: _error),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_message!, style: AppTextStyle.footnote.of(context)),
          ),
        if (result != null)
          generateSection(
            title: l.requestActualRoute,
            items: [
              DetailRow.text(title: l.target, value: result.url),
              DetailRow.text(
                title: l.rule,
                value: '${result.rule} ${result.rulePayload}'.trim(),
              ),
              DetailRow.text(
                title: l.proxyChains,
                value: result.chains.reversed.join(' → '),
              ),
            ],
            footer: l.requestActualRouteNote,
          ),
      ],
    );
  }
}

class _RequestRuleForm extends StatefulWidget {
  const _RequestRuleForm({
    required this.domain,
    required this.profile,
    required this.targets,
  });

  final String domain;
  final String profile;
  final List<String> targets;

  @override
  State<_RequestRuleForm> createState() => _RequestRuleFormState();
}

class _RequestRuleFormState extends State<_RequestRuleForm> {
  var _action = RuleAction.DOMAIN;
  var _target = 'DIRECT';

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return FormPage(
      title: l.requestCreateRule,
      onSave: () => Navigator.of(context).pop(
        Rule(
          id: snowflake.id,
          ruleAction: _action,
          content: widget.domain,
          ruleTarget: _target,
        ),
      ),
      children: [
        generateSection(
          items: [
            DetailRow.text(title: l.profile, value: widget.profile),
            DetailRow.text(title: l.host, value: widget.domain),
            ListItem<RuleAction>.options(
              title: Text(l.proxyType),
              options: const [RuleAction.DOMAIN, RuleAction.DOMAIN_SUFFIX],
              value: _action,
              textBuilder: (action) => action.name,
              onChanged: (action) => setState(() => _action = action),
            ),
            ListItem<String>.options(
              title: Text(l.splitStrategy),
              options: widget.targets,
              value: _target,
              textBuilder: (target) => target,
              onChanged: (target) => setState(() => _target = target),
            ),
          ],
          footer: l.requestRulePriorityNote,
        ),
      ],
    );
  }
}
