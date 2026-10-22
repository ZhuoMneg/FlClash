import 'dart:async';

import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/routing.dart';
import 'package:fl_clash/views/routing_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _ApplyAction extends SetupAction {
  final List<int?> applied = [];
  bool fail = false;

  @override
  void build() {}

  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    applied.add(ref.read(currentProfileIdProvider));
    if (fail) throw StateError('apply failed');
    return true;
  }
}

void main() {
  testWidgets('a failed apply clears applying and supports retry', (
    tester,
  ) async {
    var failures = true;
    final session = RoutingApplySession(
      isCurrent: () => true,
      apply: () async {
        if (failures) throw StateError('failure');
        return true;
      },
    );
    addTearDown(session.dispose);
    session.changed();
    await tester.pump(const Duration(milliseconds: 400));
    expect(session.state, RoutingApplyState.failed);
    failures = false;
    await session.applyNow();
    expect(session.state, RoutingApplyState.applied);
  });

  testWidgets('a queued edit never applies after changing the active profile', (
    tester,
  ) async {
    var current = true;
    var applies = 0;
    final session = RoutingApplySession(
      isCurrent: () => current,
      apply: () async {
        applies++;
        return true;
      },
    );
    addTearDown(session.dispose);
    session.changed();
    current = false;
    await tester.pump(const Duration(seconds: 1));
    expect(applies, 0);
  });

  testWidgets('edits made during an apply run once more and disposal is safe', (
    tester,
  ) async {
    final first = Completer<bool>();
    var applies = 0;
    final session = RoutingApplySession(
      isCurrent: () => true,
      apply: () {
        applies++;
        return applies == 1 ? first.future : Future.value(true);
      },
    );
    session.changed();
    await tester.pump(const Duration(milliseconds: 400));
    expect(session.state, RoutingApplyState.applying);
    session.changed();
    first.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(applies, 2);
    expect(session.state, RoutingApplyState.applied);
    session.changed();
    session.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(applies, 2);
  });

  group('routing editor', () {
    late db.Database database;
    late ProviderContainer container;
    late _ApplyAction action;
    var closed = false;
    const profiles = [
      Profile(
        id: 1,
        label: 'First profile',
        type: ProfileType.custom,
        autoUpdateDuration: Duration.zero,
      ),
      Profile(
        id: 2,
        label: 'Second profile',
        type: ProfileType.custom,
        autoUpdateDuration: Duration.zero,
      ),
    ];

    setUp(() async {
      closed = false;
      database = db.Database(NativeDatabase.memory());
      db.database = database;
      await database.profilesDao.putAll(
        profiles.map((profile) => profile.toCompanion()),
      );
      action = _ApplyAction();
      container = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(() => TestProfiles(profiles)),
          currentProfileIdProvider.overrideWithBuild((_, _) => 1),
          setupActionProvider.overrideWith(() => action),
        ],
      );
      globalState.container = container;
      container.read(viewSizeProvider.notifier).value = const Size(1400, 1000);
    });

    tearDown(() async {
      if (!closed) {
        container.dispose();
        await database.close();
      }
    });

    Future<void> pumpEditor(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: RoutingView()),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    Future<void> closeEditor(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(database.close);
      closed = true;
      await tester.pump();
    }

    Future<void> tapApply(WidgetTester tester) async {
      final button = find.byTooltip('Apply routing changes');
      if (button.evaluate().isNotEmpty) {
        await tester.tap(button);
      } else {
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply routing changes'));
      }
      await tester.pumpAndSettle();
    }

    testWidgets(
      'committed rule saves apply without disposing the routing page',
      (tester) async {
        await pumpEditor(tester);
        expect(find.text('Routing · First profile'), findsOneWidget);
        await tester.runAsync(
          () => database.rulesDao.putRule(
            const Rule(id: 1, content: 'example.com', ruleTarget: 'DIRECT'),
            profileId: 1,
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(action.applied, [1]);
        expect(
          find.textContaining('Applied to the current profile'),
          findsOneWidget,
        );
        await closeEditor(tester);
      },
    );

    testWidgets(
      'an unrelated profile edit does not apply the current configuration',
      (tester) async {
        await pumpEditor(tester);
        await tester.runAsync(
          () => database.rulesDao.putRule(
            const Rule(id: 2, content: 'other.example', ruleTarget: 'DIRECT'),
            profileId: 2,
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(action.applied, isEmpty);
        await closeEditor(tester);
      },
    );

    testWidgets('a failed manual apply exposes retry and clears its spinner', (
      tester,
    ) async {
      await pumpEditor(tester);
      action.fail = true;
      await tapApply(tester);
      expect(find.textContaining('Apply failed. Try again.'), findsOneWidget);
      action.fail = false;
      await tapApply(tester);
      expect(
        find.textContaining('Applied to the current profile'),
        findsOneWidget,
      );
      expect(action.applied, [1, 1]);
      await closeEditor(tester);
    });
  });
}
