import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/dav_client.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart' show DateFormat;

String backupVersionLabel(BuildContext context, DAVBackup backup) =>
    backup.createdAt == null
    ? context.appLocalizations.backupLegacy
    : DateFormat.yMd().add_Hms().format(backup.createdAt!.toLocal());

class BackupVersionsSheet extends StatefulWidget {
  const BackupVersionsSheet({
    super.key,
    required this.backups,
    this.onDelete,
    this.onSaveNote,
    this.loadNote,
  });

  final List<DAVBackup> backups;
  final Future<DAVBackup> Function(DAVBackup backup)? loadNote;
  final Future<void> Function(DAVBackup backup)? onDelete;
  final Future<void> Function(DAVBackup backup, String note)? onSaveNote;

  @override
  State<BackupVersionsSheet> createState() => _BackupVersionsSheetState();
}

class _BackupVersionsSheetState extends State<BackupVersionsSheet> {
  late final List<DAVBackup> _backups = List.of(widget.backups);
  String _query = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.loadNote != null) unawaited(_loadNotes());
  }

  Future<void> _loadNotes() async {
    final pending = List.of(_backups).iterator;
    Future<void> worker() async {
      while (mounted && pending.moveNext()) {
        final backup = pending.current;
        try {
          final updated = await widget.loadNote!(backup);
          if (!mounted) return;
          final index = _backups.indexOf(backup);
          if (index >= 0 && updated.note != backup.note) {
            setState(() => _backups[index] = updated);
          }
        } catch (error) {
          commonPrint.log(
            'Backup note unavailable: $error',
            logLevel: LogLevel.warning,
          );
        }
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
  }

  Future<void> _run(
    Future<void> Function() task,
    VoidCallback onSuccess,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
      if (mounted) setState(onSuccess);
    } catch (error) {
      if (mounted) {
        context.showNotifier(error.toString(), level: MessageLevel.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editNote(DAVBackup backup) async {
    final note = await dialogs.showCommonDialog<String>(
      context: context,
      child: InputDialog(
        title: context.appLocalizations.backupNote,
        value: backup.note,
        maxLength: 200,
        resetValue: '',
      ),
    );
    if (note == null || !mounted || note.trim() == backup.note) return;
    await _run(() => widget.onSaveNote!(backup, note.trim()), () {
      final index = _backups.indexWhere((item) => item.name == backup.name);
      if (index >= 0) _backups[index] = backup.withNote(note.trim());
    });
  }

  Future<void> _delete(DAVBackup backup) async {
    final l = context.appLocalizations;
    final confirmed = await dialogs.showMessage(
      context: context,
      title: l.delete,
      message: TextSpan(
        text: l.backupDeleteConfirm(backupVersionLabel(context, backup)),
      ),
      confirmText: l.delete,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => widget.onDelete!(backup),
      () => _backups.removeWhere((item) => item.name == backup.name),
    );
  }

  List<CommonPopupMenuItem> _menu(DAVBackup backup) {
    final l = context.appLocalizations;
    return [
      CommonPopupMenuItem(
        glyph: AppGlyphs.info,
        label: l.details(l.backup),
        onPressed: () => unawaited(
          dialogs.showMessage(
            context: context,
            title: l.details(l.backup),
            message: TextSpan(
              text: [
                backupVersionLabel(context, backup),
                if (backup.note.isNotEmpty) backup.note,
                backup.name,
              ].join('\n\n'),
            ),
          ),
        ),
      ),
      if (widget.onSaveNote != null)
        CommonPopupMenuItem(
          glyph: AppGlyphs.edit,
          label: l.backupNote,
          onPressed: () => unawaited(_editNote(backup)),
        ),
      if (widget.onDelete != null)
        CommonPopupMenuItem(
          glyph: AppGlyphs.delete,
          label: l.delete,
          danger: true,
          onPressed: () => unawaited(_delete(backup)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final search = SearchQuery(_query);
    final matches = _backups
        .whereMatches(
          search,
          (backup) => [
            backupVersionLabel(context, backup),
            backup.note,
            backup.name,
          ],
        )
        .toList();
    return CommonScaffold(
      isLoading: _busy,
      title: l.selectBackupVersion,
      searchState: AppBarSearchState(
        onSearch: (query) => setState(() => _query = query),
      ),
      body: Builder(
        builder: (context) => NullStatusSwitcher(
          isEmpty: matches.isEmpty,
          isSearching: search.isNotEmpty,
          nullStatus: NullStatus(label: l.noBackupFileFound),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
              top: context.contentTopPadding,
              bottom: 20 + context.bottomInset,
            ),
            children: [
              generateSection(
                footer: l.backupHistoryHelp,
                items: [
                  for (final backup in matches)
                    ContextMenuRegion(
                      menuItems: _busy ? null : _menu(backup),
                      child: ListItem(
                        title: TooltipLabel(
                          [
                            backupVersionLabel(context, backup),
                            if (identical(backup, _backups.first))
                              l.backupLatest,
                          ].join(' · '),
                        ),
                        subtitle: backup.note.isEmpty
                            ? null
                            : Text(backup.note),
                        onTap: _busy
                            ? null
                            : () => Navigator.of(context).pop(backup),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
