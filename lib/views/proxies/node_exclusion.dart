import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class NodeExclusionForm extends ConsumerStatefulWidget {
  const NodeExclusionForm({super.key});

  @override
  ConsumerState<NodeExclusionForm> createState() => _NodeExclusionFormState();
}

class _NodeExclusionFormState extends ConsumerState<NodeExclusionForm> {
  late final TextEditingController _controller;
  late bool _plainText;
  Timer? _debounce;
  int _request = 0;
  Set<String> _matches = {};
  String? _invalidPattern;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(proxiesStyleSettingProvider);
    _controller = TextEditingController(text: settings.nodeExcludeFilter);
    _plainText = settings.nodeExcludePlainText;
    ref.listenManual(groupsProvider.select(ProxyFilterNames.new), (_, _) {
      _schedulePreview();
    });
    unawaited(_preview());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _request++;
    _controller.dispose();
    super.dispose();
  }

  void _schedulePreview() {
    _request++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      unawaited(_preview());
    });
  }

  Future<void> _preview() async {
    final request = ++_request;
    final pattern = _controller.text.trim();
    String? invalid;
    if (!_plainText) {
      try {
        RegExp(pattern);
      } on FormatException catch (error) {
        invalid = error.message;
      }
    }
    final names = ProxyFilterNames(ref.read(groupsProvider)).names.toList();
    final matches = invalid != null
        ? <String>{}
        : await compute(matchProxyNameFilter, (
            pattern: pattern,
            names: names,
            plainText: _plainText,
          ));
    if (!mounted || request != _request) return;
    setState(() {
      _invalidPattern = invalid;
      _matches = matches;
    });
  }

  void _save() {
    if (!_plainText) {
      try {
        RegExp(_controller.text.trim());
      } on FormatException catch (error) {
        setState(() => _invalidPattern = error.message);
        return;
      }
    }
    ref
        .read(proxiesStyleSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            nodeExcludeFilter: _controller.text.trim(),
            nodeExcludePlainText: _plainText,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return FormPage(
      title: l.nodeExclusion,
      onSave: _save,
      error: _invalidPattern == null
          ? null
          : l.customIssueInvalidFilter(l.regex, _invalidPattern!),
      children: [
        generateSection(
          footer: l.nodeExclusionHelp,
          items: [
            ListItem<bool>.options(
              title: Text(l.nodeExclusionMode),
              options: const [true, false],
              value: _plainText,
              textBuilder: (value) => value ? l.nodeFilterPlainText : l.regex,
              onChanged: (value) {
                setState(() {
                  _plainText = value;
                  _invalidPattern = null;
                });
                _schedulePreview();
              },
            ),
            FormRow(
              title: l.filter,
              invalid: _invalidPattern != null,
              trailing: FormRowTextField(
                controller: _controller,
                hintText: _plainText
                    ? l.nodeFilterPlainExample
                    : l.nodeFilterRegexExample,
                autocorrect: false,
                onChanged: (_) => _schedulePreview(),
              ),
            ),
          ],
        ),
        generateSection(
          title: l.nodeFilterMatches(_matches.length),
          footer: _plainText
              ? l.nodeFilterPlainExample
              : l.nodeFilterRegexExample,
          items: [
            if (_matches.isEmpty)
              DecorationListItem(title: Text(l.nodeFilterNoMatches))
            else
              for (final name in _matches.take(5))
                DecorationListItem(title: TooltipLabel(name)),
          ],
        ),
      ],
    );
  }
}
