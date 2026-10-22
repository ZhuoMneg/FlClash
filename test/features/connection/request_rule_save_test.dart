import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/connection/request_routing_actions.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

class _ApplyAction extends SetupAction {
  final List<int?> applied = [];
  final List<List<Rule>> persistedAtApply = [];
  bool result = true;

  @override
  void build() {}

  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    final id = ref.read(currentProfileIdProvider);
    applied.add(id);
    persistedAtApply.add(
      await db.database.rulesDao.queryProfileRules(id!).get(),
    );
    return result;
  }
}

void main() {
  late db.Database database;
  late ProviderContainer container;
  late _ApplyAction action;
  late WidgetRef ref;
  const profiles = [
    Profile(id: 1, type: ProfileType.custom, autoUpdateDuration: Duration.zero),
    Profile(id: 2, type: ProfileType.custom, autoUpdateDuration: Duration.zero),
    Profile(
      id: 3,
      type: ProfileType.url,
      extendType: ExtendType.script,
      autoUpdateDuration: Duration.zero,
    ),
  ];
  const rule = Rule(id: 42, content: 'example.com', ruleTarget: 'DIRECT');

  setUp(() async {
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
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: Consumer(
            builder: (context, widgetRef, _) {
              ref = widgetRef;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'a confirmed domain rule persists before applying and cannot duplicate',
    (tester) async {
      await mount(tester);
      final result = await tester.runAsync(
        () => saveRequestRule(ref, profileId: 1, rule: rule),
      );
      expect(result, RequestRuleSaveResult.applied);
      expect(action.applied, [1]);
      expect(action.persistedAtApply.single.single.content, 'example.com');
      final duplicate = await tester.runAsync(
        () => saveRequestRule(ref, profileId: 1, rule: rule.copyWith(id: 43)),
      );
      expect(duplicate, RequestRuleSaveResult.duplicate);
      expect(action.applied, [1]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'switching profiles before confirmation writes and applies nothing',
    (tester) async {
      await mount(tester);
      container.read(currentProfileIdProvider.notifier).value = 2;
      final result = await tester.runAsync(
        () => saveRequestRule(ref, profileId: 1, rule: rule),
      );
      expect(result, RequestRuleSaveResult.inactive);
      expect(
        await tester.runAsync(
          () => database.rulesDao.queryProfileRules(1).get(),
        ),
        isEmpty,
      );
      expect(action.applied, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'script extensions cannot silently save an unused standard rule',
    (tester) async {
      await mount(tester);
      container.read(currentProfileIdProvider.notifier).value = 3;
      final result = await tester.runAsync(
        () => saveRequestRule(ref, profileId: 3, rule: rule),
      );
      expect(result, RequestRuleSaveResult.inactive);
      expect(action.applied, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'apply failure keeps the saved rule and reports retryable failure',
    (tester) async {
      await mount(tester);
      action.result = false;
      final result = await tester.runAsync(
        () => saveRequestRule(ref, profileId: 1, rule: rule),
      );
      expect(result, RequestRuleSaveResult.failed);
      expect(
        await tester.runAsync(
          () => database.rulesDao.queryProfileRules(1).get(),
        ),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
