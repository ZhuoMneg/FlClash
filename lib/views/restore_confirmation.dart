import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

typedef RestoreSelection = ({
  RestoreOption option,
  RestoreStrategy strategy,
  bool keepWebDAV,
});

class RestoreConfirmationForm extends StatefulWidget {
  const RestoreConfirmationForm({
    super.key,
    required this.backupLabel,
    required this.strategy,
    this.hasWebDAV = false,
  });

  final String backupLabel;
  final RestoreStrategy strategy;
  final bool hasWebDAV;

  @override
  State<RestoreConfirmationForm> createState() =>
      _RestoreConfirmationFormState();
}

class _RestoreConfirmationFormState extends State<RestoreConfirmationForm> {
  RestoreOption _option = RestoreOption.onlyProfiles;
  late RestoreStrategy _strategy = widget.strategy;
  bool _keepWebDAV = true;

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return FormPage(
      title: l.restore,
      saveLabel: l.restore,
      onSave: () => Navigator.of(context).pop<RestoreSelection>((
        option: _option,
        strategy: _strategy,
        keepWebDAV: widget.hasWebDAV && _keepWebDAV,
      )),
      children: [
        generateSection(
          items: [
            DecorationListItem(
              title: Text(l.backup),
              subtitle: Text(widget.backupLabel),
            ),
          ],
        ),
        generateSection(
          footer: _strategy == RestoreStrategy.override
              ? l.backupRestoreOverrideHelp
              : l.backupRestoreMergeHelp,
          items: [
            ListItem<RestoreOption>.options(
              title: Text(l.backupRestoreScope),
              options: RestoreOption.values,
              value: _option,
              textBuilder: (option) => option == RestoreOption.onlyProfiles
                  ? l.restoreOnlyConfig
                  : l.restoreAllData,
              onChanged: (option) => setState(() => _option = option),
            ),
            ListItem<RestoreStrategy>.options(
              title: Text(l.restoreStrategy),
              options: RestoreStrategy.values,
              value: _strategy,
              textBuilder: (strategy) => strategy.label,
              onChanged: (strategy) => setState(() => _strategy = strategy),
            ),
          ],
        ),
        if (widget.hasWebDAV && _option == RestoreOption.all)
          generateSection(
            footer: l.backupKeepWebDAVHelp,
            items: [
              ListItem.toggle(
                title: Text(l.backupKeepWebDAV),
                value: _keepWebDAV,
                onChanged: (value) => setState(() => _keepWebDAV = value),
              ),
            ],
          ),
      ],
    );
  }
}
