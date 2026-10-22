import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/restore_confirmation.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  testWidgets(
    'confirmation collects scope, strategy and account preservation together',
    (tester) async {
      final container = ProviderContainer(
        overrides: [profilesProvider.overrideWith(TestProfiles.new)],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      container.read(viewSizeProvider.notifier).value = const Size(1200, 1000);
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      RestoreSelection? result;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestApp(
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showFormSheet<RestoreSelection>(
                      context: context,
                      builder: (_) => const RestoreConfirmationForm(
                        backupLabel: '2026-10-20 09:00',
                        strategy: RestoreStrategy.compatible,
                        hasWebDAV: true,
                      ),
                    );
                  },
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
      expect(find.text('2026-10-20 09:00'), findsOneWidget);
      expect(find.text('Restore strategy'), findsOneWidget);
      await tester.tap(find.text('Restore scope'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore all data').last);
      await tester.pumpAndSettle();
      expect(find.text('Keep current WebDAV account'), findsOneWidget);
      final confirm = find.widgetWithText(TextButton, 'Restore');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(result?.option, RestoreOption.all);
      expect(result?.strategy, RestoreStrategy.compatible);
      expect(result?.keepWebDAV, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
