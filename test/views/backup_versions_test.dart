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
    ValueChanged<DAVBackup?> onResult,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => onResult(
                  await showSheet<DAVBackup>(
                    context: context,
                    builder: (_) => BackupVersionsSheet(backups: backups),
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

  testWidgets('history picker returns the chosen older backup', (tester) async {
    DAVBackup? chosen;
    final backups = [
      DAVBackup(name: 'newer.zip', createdAt: DateTime.utc(2026, 10, 20)),
      DAVBackup(name: 'older.zip', createdAt: DateTime.utc(2026, 10, 19)),
    ];
    await open(tester, backups, (value) => chosen = value);
    expect(find.text('Select backup version'), findsOneWidget);
    await tester.tap(find.text('older.zip'));
    await tester.pumpAndSettle();
    expect(chosen, same(backups.last));
  });

  testWidgets('empty history has an explicit empty state', (tester) async {
    await open(tester, [], (_) {});
    expect(find.text('No backups found'), findsOneWidget);
  });
}
