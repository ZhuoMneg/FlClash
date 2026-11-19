import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yaml/yaml.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

class _NoApply extends SetupAction {
  @override
  void applyProfileDebounce({bool silence = false, bool force = false}) {}

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) async =>
      true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  late _MockCoreHandlerInterface core;
  late ProviderContainer container;

  setUpAll(() async {
    loadAppLocalizations(const Locale('en'));
    home = Directory.systemTemp.createTempSync('flclash-profiles-action-');
    await useAppPaths(home);
  });

  tearDownAll(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  setUp(() {
    core = _MockCoreHandlerInterface();
    when(() => core.validateConfig(any())).thenAnswer((_) async => null);
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
  });

  void decodesTo(String link, List<Map<String, dynamic>> proxies) {
    when(
      () => core.decodeShareLinks([link]),
    ).thenAnswer((_) async => [proxies]);
  }

  Future<void> pumpHost(WidgetTester tester) async {
    const size = Size(1200, 1000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(viewSizeProvider.notifier).value = size;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: SizedBox()),
      ),
    );
  }

  Future<List<Map>> savedProxies(Profile profile) async {
    final config = loadYaml(await (await profile.file).readAsString()) as Map;
    return [for (final proxy in config['proxies'] as List) proxy as Map];
  }

  for (final status in [200, 500]) {
    test(
      'a slow old subscription cannot replace the new source ($status)',
      () async {
        final oldOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        addTearDown(() => HttpOverrides.global = oldOverrides);
        PackageInfo? previousPackageInfo;
        try {
          previousPackageInfo = globalState.packageInfo;
        } on Error {
          // The first test to use package information initializes the late field.
        }
        addTearDown(() {
          if (previousPackageInfo != null) {
            globalState.packageInfo = previousPackageInfo;
          }
          globalState.container = container;
        });
        globalState.packageInfo = PackageInfo(
          appName: 'FlClash',
          packageName: 'test',
          version: '1',
          buildNumber: '1',
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final arrived = Completer<void>();
        final release = Completer<void>();
        final deleteArrived = Completer<void>();
        final deleteRelease = Completer<void>();
        server.listen((request) async {
          if (request.uri.path == '/old') {
            arrived.complete();
            await release.future;
            request.response.statusCode = status;
            request.response.write('source: old\n');
          } else if (request.uri.path == '/delete') {
            deleteArrived.complete();
            await deleteRelease.future;
            request.response.write('source: deleted\n');
          } else {
            request.response.write('source: new\n');
          }
          await request.response.close();
        });
        final old = Profile.normal(
          label: 'race',
          url: 'http://127.0.0.1:${server.port}/old',
        );
        final next = old.copyWith(url: 'http://127.0.0.1:${server.port}/new');
        final testContainer = ProviderContainer(
          overrides: [
            profilesProvider.overrideWith(() => TestProfiles([old])),
            currentProfileIdProvider.overrideWithBuild((_, _) => old.id),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
            setupActionProvider.overrideWith(_NoApply.new),
          ],
        );
        addTearDown(testContainer.dispose);
        globalState.container = testContainer;
        final action = testContainer.read(profilesActionProvider.notifier);
        final first = action.updateProfile(old);
        await arrived.future;
        await action.updateProfile(next);
        release.complete();
        await first;
        expect(testContainer.read(profilesProvider).single.url, next.url);
        expect(await (await next.file).readAsString(), 'source: new\n');

        final deleted = next.copyWith(
          url: 'http://127.0.0.1:${server.port}/delete',
        );
        when(() => core.clearEffect(any())).thenAnswer((_) async {});
        final pending = action.updateProfile(deleted);
        await deleteArrived.future;
        testContainer.read(currentProfileIdProvider.notifier).value = null;
        await action.deleteProfile(deleted.id);
        deleteRelease.complete();
        await pending;
        expect(testContainer.read(profilesProvider), isEmpty);
        expect(
          await File(
            await appPath.getProfilePath(deleted.id.toString()),
          ).exists(),
          isFalse,
        );
      },
    );
  }

  group('addProfileFromLink with a share link', () {
    test('saves a file profile named after the proxy it holds', () async {
      const link = 'vless://id@hk.example.com:443#HK';
      decodesTo(link, [
        {'name': 'HK', 'type': 'vless', 'server': 'hk.example.com'},
      ]);

      await container
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(link);

      final profile = container.read(profilesProvider).single;
      expect(profile.type, ProfileType.file);
      expect(profile.url, isEmpty);
      expect(profile.label, 'HK');
      expect(await savedProxies(profile), [
        {'name': 'HK', 'type': 'vless', 'server': 'hk.example.com'},
      ]);
      verify(() => core.validateConfig(any())).called(1);
    });

    test('names an unnamed proxy after its server', () async {
      const link = 'ss://YWVzLTEyOC1nY206cGFzcw@ss.example.com:8388';
      decodesTo(link, [
        {'name': '', 'type': 'ss', 'server': 'ss.example.com'},
      ]);

      await container
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(link, label: 'Mine');

      final profile = container.read(profilesProvider).single;
      expect(profile.label, 'Mine');
      expect((await savedProxies(profile)).single['name'], 'ss.example.com');
    });

    test('moves a proxy off a name mihomo reserves', () async {
      const link = 'trojan://pass@t.example.com:443#DIRECT';
      decodesTo(link, [
        {'name': 'DIRECT', 'type': 'trojan', 'server': 't.example.com'},
      ]);

      await container
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(link);

      final profile = container.read(profilesProvider).single;
      expect((await savedProxies(profile)).single['name'], 'DIRECT-01');
    });

    testWidgets('reports a link no proxy can be read from and adds nothing', (
      tester,
    ) async {
      const link = 'vmess://not-base64';
      decodesTo(link, const []);
      await pumpHost(tester);

      await container
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(link);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text(currentAppLocalizations.shareLinksInvalid), findsOne);
      expect(container.read(profilesProvider), isEmpty);
      verifyNever(() => core.validateConfig(any()));
    });
  });

  group('addProfilesFromLinks with share links', () {
    const links = [
      'vless://id@hk.example.com:443#HK',
      'trojan://pass@hk2.example.com:443#HK',
      'ss://YWVzLTEyOC1nY206cGFzcw@ss.example.com:8388',
    ];

    test('makes one profile of all their proxies', () async {
      when(() => core.decodeShareLinks(links)).thenAnswer(
        (_) async => [
          [
            {'name': 'HK', 'type': 'vless', 'server': 'hk.example.com'},
          ],
          [
            {'name': 'HK', 'type': 'trojan', 'server': 'hk2.example.com'},
          ],
          [
            {'name': '', 'type': 'ss', 'server': 'ss.example.com'},
          ],
        ],
      );

      await container
          .read(profilesActionProvider.notifier)
          .addProfilesFromLinks(links);

      final profile = container.read(profilesProvider).single;
      expect(profile.type, ProfileType.file);
      expect(
        profile.label,
        currentAppLocalizations.proxiesProfileLabel('HK', 3),
      );
      expect(
        [for (final proxy in await savedProxies(profile)) proxy['name']],
        ['HK', 'HK-01', 'ss.example.com'],
      );
      verify(() => core.decodeShareLinks(links)).called(1);
    });

    testWidgets('names the link no proxy can be read from and adds nothing', (
      tester,
    ) async {
      when(() => core.decodeShareLinks(links)).thenAnswer(
        (_) async => [
          [
            {'name': 'HK', 'type': 'vless', 'server': 'hk.example.com'},
          ],
          const [],
          [
            {'name': '', 'type': 'ss', 'server': 'ss.example.com'},
          ],
        ],
      );
      await pumpHost(tester);

      await container
          .read(profilesActionProvider.notifier)
          .addProfilesFromLinks(links);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final l10n = currentAppLocalizations;
      expect(
        find.text(
          l10n.failedItem(links.first, l10n.shareLinkUnreadable(links[1])),
        ),
        findsOne,
      );
      expect(container.read(profilesProvider), isEmpty);
      verifyNever(() => core.validateConfig(any()));
    });
  });
}
