import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/advanced.dart';
import 'package:fl_clash/views/tools.dart';
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
    container.read(viewSizeProvider.notifier).value = const Size(1400, 1400);
  });
  tearDown(() => container.dispose());

  Future<void> openSearch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ToolsView(settingsOnly: true)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
  }

  testWidgets('nested setting terms find the existing destination', (
    tester,
  ) async {
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'DNS');
    await tester.pumpAndSettle();
    expect(find.text('Advanced configuration'), findsOneWidget);
    expect(find.text('Language'), findsNothing);
    await tester.tap(find.text('Advanced configuration'));
    await tester.pumpAndSettle();
    expect(find.byType(AdvancedConfigView), findsOneWidget);
    expect(find.text('DNS'), findsWidgets);
  });

  testWidgets(
    'search clears back to the full settings and keeps hidden developer tools hidden',
    (tester) async {
      await openSearch(tester);
      final search = find.byType(TextField);
      await tester.enterText(search, 'WebDAV');
      await tester.pumpAndSettle();
      expect(find.text('Backup and restore'), findsOneWidget);
      expect(find.text('Theme'), findsNothing);
      await tester.enterText(search, 'Developer');
      await tester.pumpAndSettle();
      expect(find.text('Developer mode'), findsNothing);
      await tester.enterText(search, 'unmatched-setting');
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsNothing);
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
    },
  );
}
