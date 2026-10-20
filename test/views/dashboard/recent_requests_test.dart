import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/widgets/recent_requests.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

TrackerInfo _request(int id) => TrackerInfo(
  id: '$id',
  start: DateTime(2026, 10, 20, 0, 0, id),
  metadata: Metadata(network: 'tcp', host: 'host$id.example'),
  chains: ['Exit $id'],
  rule: 'DOMAIN',
  rulePayload: 'host$id.example',
);

void main() {
  late ProviderContainer container;
  setUp(() {
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    globalState.container = container;
  });
  tearDown(() => container.dispose());

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: Center(
            child: DashboardDensityScope(
              density: DashboardDensity.compact,
              scale: 1,
              child: SizedBox(
                width: 380,
                height: 152,
                child: RecentRequestsCard(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('shows the newest three requests and their actual exits', (
    tester,
  ) async {
    final requests = container.read(requestsProvider.notifier);
    for (var id = 0; id < 5; id++) {
      requests.addRequest(_request(id));
    }
    await pumpCard(tester);
    expect(find.text('host0.example'), findsNothing);
    expect(find.text('host1.example'), findsNothing);
    expect(find.text('host4.example'), findsOneWidget);
    expect(find.text('Exit 4'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('host4.example')).dy,
      lessThan(tester.getTopLeft(find.text('host3.example')).dy),
    );
    await tester.tap(find.text('host4.example'));
    await tester.pumpAndSettle();
    expect(find.byType(TrackerInfoDetailView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets(
    'updates the preview, opens request history and cancels pending work',
    (tester) async {
      await pumpCard(tester);
      final requests = container.read(requestsProvider.notifier);
      requests.addRequest(_request(6));
      await tester.pump(renderThrottleDuration);
      await tester.pump();
      expect(find.text('host6.example'), findsOneWidget);
      await tester.tap(find.text('Recent requests'));
      await tester.pump();
      expect(container.read(currentPageLabelProvider), PageLabel.requests);
      requests.addRequest(_request(7));
      await close(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
