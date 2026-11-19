import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/common/release_asset.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _StalledHttpClient extends Fake implements HttpClient {
  @override
  Duration? connectionTimeout;

  @override
  String Function(Uri url)? findProxy;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Completer<HttpClientRequest>().future;
}

class _HostAdapter implements HttpClientAdapter {
  _HostAdapter(this.byHost);

  final Map<String, ResponseBody Function()> byHost;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return byHost[options.uri.host]!();
  }

  @override
  void close({bool force = false}) {}
}

class _PathAdapter implements HttpClientAdapter {
  _PathAdapter(this.byPath);

  final Map<String, ResponseBody Function()> byPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return byPath[options.uri.path]!();
  }

  @override
  void close({bool force = false}) {}
}

class _PendingAdapter implements HttpClientAdapter {
  int calls = 0;
  int cancellations = 0;
  final started = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    if (!started.isCompleted) started.complete();
    cancelFuture?.then((_) => cancellations++);
    return Completer<ResponseBody>().future;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'compares custom release builds without offering the installed build',
    () async {
      globalState.packageInfo = PackageInfo(
        appName: 'FlClash',
        packageName: 'com.follow.clash',
        version: '0.9.1',
        buildNumber: '12',
      );
      String tag = 'build-v0.9.1+12';
      final client = Request()
        ..dio.httpClientAdapter = _HostAdapter({
          'api.github.com': () => ResponseBody.fromString(
            jsonEncode({'tag_name': tag}),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
        });
      expect(await client.checkForUpdate(), isNull);
      tag = 'build-v0.9.1+13';
      expect(await client.checkForUpdate(), {'tag_name': tag});
      tag = 'build-v0.9.2+1';
      expect(await client.checkForUpdate(), {'tag_name': tag});
      tag = 'build-v0.9.0+99';
      expect(await client.checkForUpdate(), isNull);
      globalState.packageInfo = PackageInfo(
        appName: 'FlClash',
        packageName: 'com.follow.clash',
        version: '0.9.2',
        buildNumber: '2026102604',
      );
      tag = 'build-v0.9.3+22';
      expect(await client.checkForUpdate(), {'tag_name': tag});
    },
    skip: updateRepository.isEmpty,
  );

  test('an unconfigured build never offers an upstream replacement', () async {
    final client = Request()
      ..dio.httpClientAdapter = _HostAdapter({
        'api.github.com': () => throw StateError('Unexpected update lookup'),
        'github.com': () => throw StateError('Unexpected update lookup'),
      });
    expect(await client.checkForUpdate(), isNull);
  }, skip: updateRepository.isNotEmpty);

  test('getTextResponseForUrl propagates the typed DioException', () async {
    // flutter_test's mocked HttpClient answers every request with HTTP 400,
    // which Dio surfaces as a badResponse DioException.
    await expectLater(
      request.getTextResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  test('getFileResponseForUrl propagates the typed DioException', () async {
    await expectLater(
      request.getFileResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  group('latestRelease', () {
    Request requestAnswering(Map<String, ResponseBody Function()> byHost) {
      return Request()..dio.httpClientAdapter = _HostAdapter(byHost);
    }

    testWidgets(
      'stalled update endpoints time out, cancel their sockets, and can be retried',
      (tester) async {
        final adapter = _PendingAdapter();
        final client = Request(updateTimeout: const Duration(milliseconds: 20))
          ..dio.httpClientAdapter = adapter;
        var settled = false;
        final outcome = expectLater(
          client.latestRelease(),
          throwsA(
            isA<DioException>().having(
              (e) => e.type,
              'type',
              DioExceptionType.receiveTimeout,
            ),
          ),
        ).whenComplete(() => settled = true);
        for (var tick = 0; tick < 10 && !settled; tick++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(settled, isTrue);
        await outcome;
        expect(adapter.calls, 2);
        expect(adapter.cancellations, 2);
        client.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) => handler.resolve(
              Response(requestOptions: options, data: {'tag_name': 'v0.9.2'}),
            ),
          ),
        );
        Map<String, dynamic>? answer;
        final retry = client.latestRelease().then((value) => answer = value);
        for (var tick = 0; tick < 10 && answer == null; tick++) {
          await tester.pump(Duration.zero);
        }
        expect(answer, {'tag_name': 'v0.9.2'});
        await retry;
      },
    );

    test('cancelling an update does not start a fallback request', () async {
      final adapter = _PendingAdapter();
      final client = Request()..dio.httpClientAdapter = adapter;
      final token = CancelToken();
      final result = client.latestRelease(cancelToken: token);
      await adapter.started.future;
      token.cancel();
      await expectLater(
        result,
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      expect(adapter.calls, 1);
    });

    test('reads the release from the API', () async {
      final request = requestAnswering({
        'api.github.com': () => ResponseBody.fromString(
          '{"tag_name":"v1.2.3","body":"notes"}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      });

      expect(await request.latestRelease(), {
        'tag_name': 'v1.2.3',
        'body': 'notes',
      });
    });

    test(
      'falls back to the release page when the API is rate limited',
      () async {
        final request = requestAnswering({
          'api.github.com': () => ResponseBody.fromString('{}', 403),
          'github.com': () => ResponseBody.fromString(
            '',
            302,
            headers: {
              HttpHeaders.locationHeader: [
                'https://github.com/owner/repo/releases/tag/v1.2.4',
              ],
            },
          ),
        });

        expect(await request.latestRelease(), {'tag_name': 'v1.2.4'});
      },
    );

    test('fails instead of answering when neither endpoint does', () async {
      final request = requestAnswering({
        'api.github.com': () => ResponseBody.fromString('{}', 403),
        'github.com': () => ResponseBody.fromString('', 503),
      });

      await expectLater(request.latestRelease(), throwsA(isA<DioException>()));
    });
  });

  group('downloadVerifiedRelease', () {
    final name = releaseAssetName(
      line: appReleaseLine,
      version: '1.2.3',
      os: ReleaseOs.android,
      arch: ReleaseArch.arm64,
      extension: 'apk',
    );
    final package = utf8.encode('package');
    final digest = sha256.convert(package).toString();
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('release');
    });

    tearDown(() => directory.delete(recursive: true));

    Request requestServing(String sums, List<int> asset) {
      return Request()
        ..releaseDio.httpClientAdapter = _PathAdapter({
          '/$releaseRepository/releases/download/v1.2.3/${updateChecksumsName('v1.2.3')}':
              () => ResponseBody.fromString(sums, 200),
          '/$releaseRepository/releases/download/v1.2.3/$name': () =>
              ResponseBody.fromBytes(asset, 200),
        });
    }

    Future<String> download(Request request) {
      return request.downloadVerifiedRelease(
        tag: 'v1.2.3',
        name: name,
        directory: directory.path,
      );
    }

    test('keeps a file matching the published digest', () async {
      final request = requestServing('$digest  ./$name\n', package);

      final path = await download(request);

      expect(await File(path).readAsBytes(), package);
    });

    test('refuses a file that does not match', () async {
      final request = requestServing('$digest  ./$name\n', utf8.encode('x'));

      await expectLater(
        download(request),
        throwsA(isA<ReleaseNotVerifiedException>()),
      );
    });

    test('refuses an asset the listing does not name', () async {
      final request = requestServing('$digest  ./other.apk\n', package);

      await expectLater(
        download(request),
        throwsA(isA<ReleaseNotVerifiedException>()),
      );
      expect(directory.listSync(), isEmpty);
    });
  });

  group('downloadTarget', () {
    test('sends a URL without credentials unchanged', () {
      final target = downloadTarget('https://example.com/a.yaml?x=1');

      expect(target.uri.toString(), 'https://example.com/a.yaml?x=1');
      expect(target.headers, isEmpty);
    });

    test('moves decoded credentials into the Authorization header', () {
      for (final url in [
        'https://me@mail.com:p:w@dav.example.com/dav/a.yaml',
        'https://me%40mail.com:p%3Aw@dav.example.com/dav/a.yaml',
      ]) {
        final target = downloadTarget(url);

        expect(target.uri.toString(), 'https://dav.example.com/dav/a.yaml');
        expect(
          target.headers[HttpHeaders.authorizationHeader],
          'Basic ${base64.encode(utf8.encode('me@mail.com:p:w'))}',
        );
      }
    });
  });

  group('decompressUnlabeled', () {
    final yaml = utf8.encode('proxies: []\n');

    test('inflates a gzip or zlib body that arrived unlabeled', () {
      for (final codec in [gzip, zlib]) {
        final body = Uint8List.fromList(codec.encode(yaml));

        expect(decompressUnlabeled(body), yaml);
      }
    });

    test('leaves a plain body untouched', () {
      final body = Uint8List.fromList(yaml);

      expect(decompressUnlabeled(body), same(body));
    });

    test('keeps a body that only starts like gzip', () {
      final body = Uint8List.fromList([0x1f, 0x8b, 1, 2, 3]);

      expect(decompressUnlabeled(body), same(body));
    });
  });

  testWidgets('a stalled download fails at the shared download deadline', (
    tester,
  ) async {
    late final Future<Response<String>> pending;
    HttpOverrides.runZoned(() {
      pending = Request().getTextResponseForUrl('http://127.0.0.1/stalled');
    }, createHttpClient: (_) => _StalledHttpClient());
    var settled = false;
    final outcome = expectLater(
      pending.whenComplete(() => settled = true),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );

    await tester.pump(downloadTimeoutDuration - const Duration(seconds: 1));
    expect(settled, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await outcome;
  });
}
