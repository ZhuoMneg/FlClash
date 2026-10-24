import 'dart:async';

import 'package:fl_clash/common/dav_client.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/backup_and_restore.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  late ProviderContainer container;
  setUp(() {
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1200, 1000);
  });
  tearDown(() => container.dispose());

  Future<void> open(
    WidgetTester tester,
    List<DAVBackup> backups,
    ValueChanged<DAVBackup?> onResult, {
    Future<DAVBackup> Function(DAVBackup)? loadNote,
    Future<void> Function(DAVBackup)? onDelete,
    Future<void> Function(DAVBackup, String)? onSaveNote,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          withStatusManager: true,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => onResult(
                  await showSheet<DAVBackup>(
                    context: context,
                    builder: (_) => BackupVersionsSheet(
                      backups: backups,
                      loadNote: loadNote,
                      onDelete: onDelete,
                      onSaveNote: onSaveNote,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'history is usable while notes are pending and ignores a closed sheet',
    (tester) async {
      final pending = Completer<DAVBackup>();
      DAVBackup? chosen;
      final backup = DAVBackup(
        name: 'pending.zip',
        createdAt: DateTime.utc(2026, 10, 20),
      );
      await open(
        tester,
        [backup],
        (value) => chosen = value,
        loadNote: (_) => pending.future,
      );
      expect(find.text('Select backup version'), findsOneWidget);
      await tester.tap(find.textContaining('Latest'));
      await tester.pumpAndSettle();
      expect(chosen?.name, backup.name);
      pending.complete(backup.withNote('Late note'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history picker returns the chosen older backup', (tester) async {
    DAVBackup? chosen;
    final backups = [
      DAVBackup(name: 'newer.zip', createdAt: DateTime.utc(2026, 10, 20)),
      DAVBackup(
        name: 'older.zip',
        createdAt: DateTime.utc(2026, 10, 19),
        note: 'Older stable setup',
      ),
    ];
    await open(tester, backups, (value) => chosen = value);
    expect(find.text('Select backup version'), findsOneWidget);
    expect(find.textContaining('Latest'), findsOneWidget);
    expect(find.text('older.zip'), findsNothing);
    await tester.tap(find.text('Older stable setup'));
    await tester.pumpAndSettle();
    expect(chosen, same(backups.last));
  });

  testWidgets('empty history has an explicit empty state', (tester) async {
    await open(tester, [], (_) {});
    expect(find.text('No backups found'), findsOneWidget);
  });

  testWidgets('legacy labels hide filenames until details are opened', (
    tester,
  ) async {
    await open(tester, [const DAVBackup(name: 'backup.zip')], (_) {});
    expect(find.textContaining('Legacy backup'), findsOneWidget);
    expect(find.text('backup.zip'), findsNothing);
    final row = tester.widget<ContextMenuRegion>(
      find.byType(ContextMenuRegion),
    );
    row.menuItems!.first.onPressed!();
    await tester.pumpAndSettle();
    expect(find.textContaining('backup.zip'), findsOneWidget);
  });

  testWidgets(
    'deleting a backup requires confirmation and updates the history',
    (tester) async {
      var deleted = 0;
      await open(
        tester,
        [const DAVBackup(name: 'backup.zip', note: 'Keep until confirmed')],
        (_) {},
        onDelete: (_) async => deleted++,
      );
      void requestDelete() {
        final row = tester.widget<ContextMenuRegion>(
          find.byType(ContextMenuRegion),
        );
        row.menuItems!.last.onPressed!();
      }

      requestDelete();
      await tester.pumpAndSettle();
      expect(deleted, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(deleted, 0);
      expect(find.text('Keep until confirmed'), findsOneWidget);
      requestDelete();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(deleted, 1);
      expect(find.text('No backups found'), findsOneWidget);
    },
  );

  testWidgets(
    'a failed deletion keeps the backup and releases the loading state',
    (tester) async {
      await open(
        tester,
        [const DAVBackup(name: 'backup.zip', note: 'Still available')],
        (_) {},
        onDelete: (_) async => throw StateError('Server refused deletion'),
      );
      final row = tester.widget<ContextMenuRegion>(
        find.byType(ContextMenuRegion),
      );
      row.menuItems!.last.onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Still available'), findsOneWidget);
      expect(
        tester
            .widget<CommonScaffold>(find.byType(CommonScaffold).first)
            .isLoading,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'notes are saved through the callback and shown without renaming archives',
    (tester) async {
      String? savedName;
      String? savedNote;
      await open(
        tester,
        [const DAVBackup(name: 'backup.zip')],
        (_) {},
        onSaveNote: (backup, note) async {
          savedName = backup.name;
          savedNote = note;
        },
      );
      final row = tester.widget<ContextMenuRegion>(
        find.byType(ContextMenuRegion),
      );
      row.menuItems!.last.onPressed!();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Before holiday');
      await tester.tap(find.widgetWithText(TextButton, 'Submit'));
      await tester.pumpAndSettle();
      expect(savedName, 'backup.zip');
      expect(savedNote, 'Before holiday');
      expect(find.text('Before holiday'), findsOneWidget);
    },
  );
}
