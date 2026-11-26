import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:riverpod/riverpod.dart';

import '../helpers/app_paths.dart';
import '../helpers/preferences.dart';

Profile _profile(int id, String label) =>
    Profile(id: id, label: label, autoUpdateDuration: Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database testDatabase;
  late Directory home;

  setUpAll(() async {
    await mockPreferences({'version': 1});
    loadAppLocalizations(const Locale('en'));
    home = Directory.systemTemp.createTempSync('flclash-backup-action-');
    await useAppPaths(home);
  });

  tearDownAll(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  setUp(() {
    testDatabase = Database(NativeDatabase.memory());
    database = testDatabase;
  });

  tearDown(() async {
    await testDatabase.close();
  });

  // AppStateManager's listen keeps the settings alive while a restore awaits.
  ProviderContainer buildContainer() {
    final container = ProviderContainer()..listen(configProvider, (_, _) {});
    addTearDown(container.dispose);
    return container;
  }

  BackupAction actionOf(ProviderContainer container) =>
      container.read(backupActionProvider.notifier);

  Map<String, Object?> configMapOf(ProviderContainer container) =>
      jsonDecode(jsonEncode(container.read(configProvider).toJson()))
          as Map<String, Object?>;

  group('backup and restore round trip', () {
    late Directory kept;

    setUp(() {
      kept = Directory.systemTemp.createTempSync('flclash-backup-kept-');
      addTearDown(() => kept.deleteSync(recursive: true));
    });

    Set<String> workDirs() => home
        .listSync()
        .map((entity) => basename(entity.path))
        .where((name) => name.startsWith('backup'))
        .toSet();

    Future<String> backupToKept(BackupAction action) async {
      final keptPath = join(kept.path, 'kept.zip');
      final delivered = await action.backup((archivePath) async {
        File(archivePath).copySync(keptPath);
        return true;
      });
      expect(delivered, isTrue);
      return keptPath;
    }

    test('missing local files fail backup before delivery', () async {
      await testDatabase.profilesDao.putAll([
        _profile(923011, 'Missing').toCompanion(),
      ]);
      var delivered = false;
      await expectLater(
        actionOf(buildContainer()).backup((_) async {
          delivered = true;
          return true;
        }),
        throwsStateError,
      );
      expect(delivered, isFalse);
    });

    test(
      'missing local script, provider, module or attachment fails',
      () async {
        final module = MitmModule(
          id: 923020,
          name: 'Local',
          lastUpdateTime: DateTime(2026),
          resources: const {'local.txt': 'backup-test-resource.txt'},
        );
        const provider = ClashProvider(id: 923021, label: 'Local');
        await testDatabase.scriptsDao.setAll([
          Script(id: 923022, label: 'Local', lastUpdateTime: DateTime(2026)),
        ]);
        await testDatabase.clashProvidersDao.putAll([provider.toCompanion()]);
        await testDatabase.mitmModulesDao.putAll([module.toCompanion()]);
        final entries = [
          BackupEntries.script(923022),
          BackupEntries.provider(provider),
          BackupEntries.mitmModule(module),
          BackupEntries.mitmResource('backup-test-resource.txt'),
        ];
        final files = [
          for (final entry in entries)
            File(BackupEntries.resolve(home.path, entry)),
        ];
        for (final file in files) {
          await file.create(recursive: true);
          await file.writeAsString('local');
        }
        addTearDown(() async {
          for (final file in files) {
            if (await file.exists()) await file.delete();
          }
        });
        for (final file in files) {
          await file.delete();
          var delivered = false;
          await expectLater(
            actionOf(buildContainer()).backup((_) async {
              delivered = true;
              return true;
            }),
            throwsStateError,
            reason: file.path,
          );
          expect(delivered, isFalse);
          await file.writeAsString('local');
        }
      },
    );

    test('custom profiles need no local file', () async {
      await testDatabase.profilesDao.putAll([
        _profile(
          923012,
          'Custom',
        ).copyWith(type: ProfileType.custom).toCompanion(),
      ]);
      expect(await backupToKept(actionOf(buildContainer())), isNotEmpty);
    });

    test(
      'remote profiles and scripts still require their saved files',
      () async {
        await testDatabase.profilesDao.putAll([
          _profile(923013, 'Remote')
              .copyWith(
                type: ProfileType.url,
                url: 'https://example.com/profile',
              )
              .toCompanion(),
        ]);
        await testDatabase.scriptsDao.setAll([
          Script(
            id: 923014,
            label: 'Remote',
            url: 'https://example.com/script',
            lastUpdateTime: DateTime(2026),
          ),
        ]);
        final profileFile = File(await appPath.getProfilePath('923013'));
        final scriptFile = File(await appPath.getScriptPath('923014'));
        addTearDown(() async {
          if (await profileFile.exists()) await profileFile.delete();
          if (await scriptFile.exists()) await scriptFile.delete();
        });
        await expectLater(
          backupToKept(actionOf(buildContainer())),
          throwsStateError,
        );
        await profileFile.create(recursive: true);
        await expectLater(
          backupToKept(actionOf(buildContainer())),
          throwsStateError,
        );
        await scriptFile.create(recursive: true);
        expect(await backupToKept(actionOf(buildContainer())), isNotEmpty);
      },
    );

    test(
      'a settings-only archive preserves existing database on override',
      () async {
        await testDatabase.profilesDao.putAll([
          _profile(923015, 'Keep').toCompanion(),
        ]);
        final source = buildContainer();
        source
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith(mixedPort: 7899));
        for (final version in [0, 1]) {
          final config = configMapOf(source)..['version'] = version;
          final archivePath = join(kept.path, 'settings-$version.zip');
          final encoder = ZipFileEncoder()..create(archivePath);
          encoder.addArchiveFile(
            ArchiveFile.string(configJsonName, jsonEncode(config)),
          );
          await encoder.close();
          final target = buildContainer();

          expect(
            await actionOf(target).restore(
              RestoreOption.all,
              (_) async => archivePath,
              strategy: RestoreStrategy.override,
            ),
            isTrue,
          );
          expect(
            (await testDatabase.profilesDao.query().get()).single.label,
            'Keep',
          );
          expect(target.read(patchClashConfigProvider).mixedPort, 7899);
        }
      },
    );

    test(
      'an empty database archive clears existing rows on override',
      () async {
        final archivePath = await backupToKept(actionOf(buildContainer()));
        await testDatabase.profilesDao.putAll([
          _profile(923016, 'Remove').toCompanion(),
        ]);
        expect(
          await actionOf(buildContainer()).restore(
            RestoreOption.all,
            (_) async => archivePath,
            strategy: RestoreStrategy.override,
          ),
          isTrue,
        );
        expect(await testDatabase.profilesDao.query().get(), isEmpty);
      },
    );

    test('restores the rows, files and settings a backup carries', () async {
      await testDatabase.profilesDao.putAll([
        _profile(1, 'Backed up').toCompanion(0),
      ]);
      final profileFile = File(await appPath.getProfilePath('1'))
        ..createSync(recursive: true)
        ..writeAsStringSync('proxies: []');
      final source = buildContainer();
      source.read(excludeSSIDsProvider.notifier).value = ['home-wifi'];
      final archivePath = await backupToKept(actionOf(source));

      await testDatabase.delete(testDatabase.profiles).go();
      profileFile.deleteSync();
      final target = buildContainer();
      final restored = await actionOf(
        target,
      ).restore(RestoreOption.all, (_) async => archivePath);

      expect(restored, isTrue);
      final stored = await testDatabase.profilesDao.query().get();
      expect(stored.map((item) => item.label), ['Backed up']);
      expect(profileFile.readAsStringSync(), 'proxies: []');
      expect(target.read(excludeSSIDsProvider), ['home-wifi']);
      expect(workDirs(), isEmpty);
    });

    test('brings back the attachments of local modules and cleans the '
        'rest', () async {
      final module = MitmModule(
        id: 9,
        name: 'Mine',
        resources: const {'own.json': 'own.json'},
        lastUpdateTime: DateTime(2026),
      );
      await testDatabase.mitmModulesDao.putAll([module.toCompanion()]);
      File(join(home.path, 'mitm', 'modules', module.fileName))
        ..createSync(recursive: true)
        ..writeAsStringSync('[Map Local]\n^https://a data="own.json"\n');
      final resources = join(home.path, 'mitm', 'resources');
      final own = File(join(resources, 'own.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      final archivePath = await backupToKept(actionOf(buildContainer()));

      own.deleteSync();
      final stale = File(join(resources, 'stale.json'))..writeAsStringSync('');
      final target = buildContainer();
      final restored = await actionOf(
        target,
      ).restore(RestoreOption.all, (_) async => archivePath);

      expect(restored, isTrue);
      expect(own.readAsStringSync(), '{}');
      expect(stale.existsSync(), isFalse);
    });

    test('removes the work directory when delivery fails', () async {
      final container = buildContainer();

      await expectLater(
        actionOf(
          container,
        ).backup((_) async => throw const SocketException('offline')),
        throwsA(isA<SocketException>()),
      );

      expect(workDirs(), isEmpty);
    });

    test('a cancelled fetch changes nothing', () async {
      final container = buildContainer();

      final restored = await actionOf(
        container,
      ).restore(RestoreOption.all, (_) async => null);

      expect(restored, isFalse);
    });

    test('an unreadable archive is reported and changes nothing', () async {
      await testDatabase.profilesDao.putAll([
        _profile(9, 'Pre-existing').toCompanion(0),
      ]);
      final bogus = File(join(kept.path, 'bogus.zip'))
        ..writeAsStringSync('not a zip');
      final container = buildContainer();

      await expectLater(
        actionOf(container).restore(RestoreOption.all, (_) async => bogus.path),
        throwsA(
          isA<MessageException>().having(
            (error) => error.message,
            'message',
            currentAppLocalizations.invalidBackupFile,
          ),
        ),
      );

      final stored = await testDatabase.profilesDao.query().get();
      expect(stored.map((item) => item.label), ['Pre-existing']);
      expect(workDirs(), isEmpty);
    });

    test('removes the staging an earlier version left behind', () async {
      final legacyArchive = File(join(home.path, 'backup.zip'))
        ..writeAsStringSync('stale');
      final legacyStaging = Directory(join(home.path, 'restore'))..createSync();
      final container = buildContainer();

      await actionOf(container).restore(RestoreOption.all, (_) async => null);

      expect(legacyArchive.existsSync(), isFalse);
      expect(legacyStaging.existsSync(), isFalse);
    });
  });

  group('applyRestore writes the database', () {
    test('inserts the profiles the backup carries', () async {
      final container = buildContainer();

      await actionOf(container).applyRestore(
        MigrationData(profiles: [_profile(1, 'From backup')]),
        RestoreOption.onlyProfiles,
      );

      final stored = await testDatabase.profilesDao.query().get();
      expect(stored.map((item) => item.label), ['From backup']);
    });

    test('an override restore drops profiles the backup omits', () async {
      final container = buildContainer();
      await testDatabase.profilesDao.putAll([
        _profile(9, 'Pre-existing').toCompanion(0),
      ]);
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) =>
                state.copyWith(restoreStrategy: RestoreStrategy.override),
          );

      await actionOf(container).applyRestore(
        MigrationData(profiles: [_profile(1, 'From backup')]),
        RestoreOption.onlyProfiles,
      );

      final stored = await testDatabase.profilesDao.query().get();
      expect(stored.map((item) => item.label), ['From backup']);
    });

    test('a compatible restore keeps profiles the backup omits', () async {
      final container = buildContainer();
      await testDatabase.profilesDao.putAll([
        _profile(9, 'Pre-existing').toCompanion(0),
      ]);
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) =>
                state.copyWith(restoreStrategy: RestoreStrategy.compatible),
          );

      await actionOf(container).applyRestore(
        MigrationData(profiles: [_profile(1, 'From backup')]),
        RestoreOption.onlyProfiles,
      );

      final stored = await testDatabase.profilesDao.query().get();
      expect(stored.map((item) => item.label).toSet(), {
        'Pre-existing',
        'From backup',
      });
    });

    test('a restore drops the cache of a provider it replaced', () async {
      const dropped = ClashProvider(
        id: 5,
        label: 'Dropped',
        url: 'https://example.com/dropped.yaml',
      );
      const kept = ClashProvider(id: 6, label: 'Kept');
      await testDatabase.clashProvidersDao.putAll(
        [dropped, kept].map((item) => item.toCompanion()),
      );
      for (final path in [
        await dropped.path,
        await dropped.compiledPath,
        await kept.path,
        await kept.compiledPath,
      ]) {
        File(path).createSync(recursive: true);
      }
      final container = buildContainer();
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) =>
                state.copyWith(restoreStrategy: RestoreStrategy.override),
          );

      await actionOf(container).applyRestore(
        const MigrationData(clashProviders: [kept]),
        RestoreOption.onlyProfiles,
      );

      expect(File(await dropped.path).existsSync(), isFalse);
      expect(File(await dropped.compiledPath).existsSync(), isFalse);
      expect(File(await kept.path).existsSync(), isTrue);
      expect(
        File(await kept.compiledPath).existsSync(),
        isFalse,
        reason: 'the restored source is compiled again on first use',
      );
    });

    test('rows that fail to restore take their files back out', () async {
      final replaced = File(await appPath.getProfilePath('41'))
        ..createSync(recursive: true)
        ..writeAsStringSync('current');
      final added = File(await appPath.getProfilePath('42'));
      final staging = Directory.systemTemp.createTempSync('flclash-staging-');
      addTearDown(() => staging.deleteSync(recursive: true));
      for (final id in [41, 42]) {
        File(BackupEntries.resolve(staging.path, BackupEntries.profile(id)))
          ..createSync(recursive: true)
          ..writeAsStringSync('from backup');
      }
      await testDatabase.customStatement(
        'CREATE TRIGGER refuse_profiles BEFORE INSERT ON profiles '
        "BEGIN SELECT RAISE(ABORT, 'refused'); END",
      );

      await expectLater(
        actionOf(buildContainer()).applyRestore(
          MigrationData(profiles: [_profile(41, 'One'), _profile(42, 'Two')]),
          RestoreOption.onlyProfiles,
          stagingDirPath: staging.path,
        ),
        throwsA(anything),
      );

      expect(replaced.readAsStringSync(), 'current');
      expect(added.existsSync(), isFalse);
    });

    test('a backup carrying only proxy groups still writes them', () async {
      await testDatabase.profiles.put(
        const Profile(id: 7, autoUpdateDuration: Duration.zero).toCompanion(),
      );
      final container = buildContainer();

      await actionOf(container).applyRestore(
        const MigrationData(
          proxyGroups: [
            ProxyGroup(
              id: 1,
              profileId: 7,
              name: 'Selector',
              type: GroupType.Selector,
            ),
          ],
        ),
        RestoreOption.onlyProfiles,
      );

      final stored = await testDatabase.proxyGroupsDao.query(7).get();
      expect(
        stored.map((item) => item.name),
        ['Selector'],
        reason:
            'proxyGroups belongs in the guard that decides whether the batch '
            'runs, not only in the batch body',
      );
    });
  });

  group('applyRestore writes the settings providers', () {
    test(
      'full restore can retain the current DAV account and chosen strategy',
      () async {
        final source = buildContainer();
        source.read(davSettingProvider.notifier).value = const DAVProps(
          uri: 'https://old-dav.example',
          user: 'old',
          fileName: 'old.zip',
        );
        final configMap = configMapOf(source);
        final target = buildContainer();
        const current = DAVProps(
          uri: 'https://current-dav.example',
          user: 'current',
          fileName: 'current.zip',
        );
        target.read(davSettingProvider.notifier).value = current;

        await actionOf(target).applyRestore(
          MigrationData(configMap: configMap),
          RestoreOption.all,
          strategy: RestoreStrategy.override,
          keepWebDAV: true,
        );
        expect(target.read(davSettingProvider), current);
        expect(
          target.read(appSettingProvider).restoreStrategy,
          RestoreStrategy.override,
        );
      },
    );

    test(
      'the per-restore strategy takes precedence over the stored default',
      () async {
        final container = buildContainer();
        await testDatabase.profilesDao.putAll([
          _profile(9, 'Pre-existing').toCompanion(0),
        ]);
        await actionOf(container).applyRestore(
          MigrationData(profiles: [_profile(1, 'Restored')]),
          RestoreOption.onlyProfiles,
          strategy: RestoreStrategy.override,
        );
        expect(
          (await testDatabase.profilesDao.query().get()).map((item) => item.id),
          [1],
        );
        expect(
          container.read(appSettingProvider).restoreStrategy,
          RestoreStrategy.override,
        );
      },
    );

    test('restores every settings provider the config carries', () async {
      final source = buildContainer();
      source
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(autoLaunch: true));
      source.read(currentProfileIdProvider.notifier).value = 42;
      source
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mixedPort: 7899));
      final configMap = configMapOf(source);

      final target = buildContainer();
      await actionOf(
        target,
      ).applyRestore(MigrationData(configMap: configMap), RestoreOption.all);

      expect(target.read(currentProfileIdProvider), 42);
      expect(target.read(appSettingProvider).autoLaunch, isTrue);
      expect(target.read(patchClashConfigProvider).mixedPort, 7899);
    });

    test(
      'a backup holding a mixed port of 0 restores the default and says so',
      () async {
        final configMap = configMapOf(buildContainer());
        (configMap['patchClashConfig']! as Map<String, Object?>)['mixed-port'] =
            0;
        final banners = <String>[];
        final print = debugPrint;
        debugPrint = (message, {wrapWidth}) => banners.add(message ?? '');
        addTearDown(() => debugPrint = print);
        final target = buildContainer();
        target
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith(mixedPort: 7899));

        await actionOf(
          target,
        ).applyRestore(MigrationData(configMap: configMap), RestoreOption.all);

        expect(
          target.read(patchClashConfigProvider).mixedPort,
          defaultMixedPort,
        );
        expect(
          banners,
          contains(
            '[APP] banner: The mixed port cannot be 0, so it was set back to 7890',
          ),
        );
      },
    );

    test('keeps the bound WebDAV account when the backup has none', () async {
      final configMap = configMapOf(buildContainer());
      const dav = DAVProps(uri: 'https://dav.example', user: 'me');
      final target = buildContainer();
      target.read(davSettingProvider.notifier).value = dav;

      await actionOf(
        target,
      ).applyRestore(MigrationData(configMap: configMap), RestoreOption.all);

      expect(target.read(davSettingProvider), dav);
    });

    test(
      'strips tunnel secrets on backup and keeps local tunnel on restore',
      () async {
        final localTunnel = NetworkTunnelSettings(
          enabled: true,
          extension: true,
          host: '179.253.249.97',
          port: 27034,
          pin: 'a' * 64,
          token: 't' * 48,
          privateKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
          publicKey: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
          ip: '10.203.77.2',
          dns: '10.203.77.1',
          profileId: 1,
        );
        final tempDir = Directory.systemTemp.createTempSync('flclash-tunnel-');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final source = buildContainer();
        source
            .read(networkSettingProvider.notifier)
            .update((state) => state.copyWith(networkTunnel: localTunnel));
        final archivePath = join(tempDir.path, 'tunnel-stripped.zip');
        final delivered = await actionOf(source).backup((path) async {
          File(path).copySync(archivePath);
          return true;
        });
        expect(delivered, isTrue);

        final data = await readBackupArchive(
          archivePath: archivePath,
          stagingDirPath: join(tempDir.path, 'staging'),
        );
        final restoredConfig = Config.fromJson(data.configMap!);
        final backupTunnel = restoredConfig.networkProps.networkTunnel;
        expect(backupTunnel.configured, isFalse);
        expect(backupTunnel.privateKey, isEmpty);
        expect(backupTunnel.token, isEmpty);

        final target = buildContainer();
        target
            .read(networkSettingProvider.notifier)
            .update((state) => state.copyWith(networkTunnel: localTunnel));
        await actionOf(target).applyRestore(data, RestoreOption.all);
        expect(target.read(networkSettingProvider).networkTunnel, localTunnel);
      },
    );

    test('keeps the picked apps when the backup lists none', () async {
      final configMap = configMapOf(buildContainer());
      const picked = AccessControlProps(
        enable: true,
        mode: AccessControlMode.acceptSelected,
        acceptList: ['com.example.browser'],
      );
      final target = buildContainer();
      target
          .read(vpnSettingProvider.notifier)
          .update((state) => state.copyWith(accessControlProps: picked));

      await actionOf(
        target,
      ).applyRestore(MigrationData(configMap: configMap), RestoreOption.all);

      expect(target.read(vpnSettingProvider).accessControlProps, picked);
    });

    test('takes the apps a backup lists from another phone', () async {
      const listed = AccessControlProps(
        enable: true,
        rejectList: ['com.example.bank'],
      );
      final source = buildContainer();
      source
          .read(vpnSettingProvider.notifier)
          .update((state) => state.copyWith(accessControlProps: listed));
      final configMap = configMapOf(source);
      final target = buildContainer();
      target
          .read(vpnSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              accessControlProps: const AccessControlProps(
                acceptList: ['com.example.browser'],
              ),
            ),
          );

      await actionOf(
        target,
      ).applyRestore(MigrationData(configMap: configMap), RestoreOption.all);

      expect(target.read(vpnSettingProvider).accessControlProps, listed);
    });

    test('leaves the settings untouched for an onlyProfiles restore', () async {
      final source = buildContainer();
      source.read(currentProfileIdProvider.notifier).value = 42;
      final configMap = configMapOf(source);

      final target = buildContainer();
      final before = target.read(currentProfileIdProvider);

      await actionOf(target).applyRestore(
        MigrationData(configMap: configMap, profiles: [_profile(1, 'P')]),
        RestoreOption.onlyProfiles,
      );

      expect(target.read(currentProfileIdProvider), before);
      expect(await testDatabase.profilesDao.query().get(), hasLength(1));
    });

    test('a backup without a config still restores the database', () async {
      final container = buildContainer();
      final before = container.read(currentProfileIdProvider);

      await actionOf(container).applyRestore(
        MigrationData(profiles: [_profile(1, 'P')]),
        RestoreOption.all,
      );

      expect(container.read(currentProfileIdProvider), before);
      expect(await testDatabase.profilesDao.query().get(), hasLength(1));
    });
  });

  group('a config with unreadable values', () {
    test('restores the rest without keeping a dropped profile', () async {
      final container = buildContainer();
      await testDatabase.profilesDao.putAll([
        _profile(9, 'Pre-existing').toCompanion(0),
      ]);
      container.read(currentProfileIdProvider.notifier).value = 9;
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) =>
                state.copyWith(restoreStrategy: RestoreStrategy.override),
          );

      await actionOf(container).applyRestore(
        MigrationData(
          configMap: const {
            'currentProfileId': 'not an int',
            'appSettingProps': {'hideIp': true},
          },
          profiles: [_profile(1, 'From backup')],
        ),
        RestoreOption.all,
      );

      final stored = await testDatabase.profilesDao.query().get();
      expect(stored.map((item) => item.label), ['From backup']);
      expect(container.read(currentProfileIdProvider), isNull);
      expect(container.read(appSettingProvider).hideIp, true);
    });
  });
}
