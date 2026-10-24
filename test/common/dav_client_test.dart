import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/dav_client.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';

import '../helpers/app_paths.dart';

class _FakeDAVClient extends DAVClient {
  _FakeDAVClient(super.dav, this.result, [this.onPing]);

  final Future<bool> result;
  final void Function()? onPing;

  @override
  Future<bool> ping() {
    onPing?.call();
    return result;
  }
}

class _RecordedRequest {
  _RecordedRequest(this.method, this.path, this.authorization, this.body);

  final String method;
  final String path;
  final String? authorization;
  final List<int> body;
}

typedef _ScriptedResponse = ({
  String method,
  int status,
  Map<String, String> headers,
});

/// A stand-in WebDAV origin: the tests drive the real client against a real
/// socket, so status handling, auth and redirects are exercised end to end.
class _TestServer {
  _TestServer(this._server) {
    unawaited(_serve());
  }

  static Future<_TestServer> start() async {
    return _TestServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  }

  final HttpServer _server;
  final List<_RecordedRequest> requests = [];
  final Map<String, List<int>> files = {};

  final List<_ScriptedResponse> responses = [];

  String get uri => 'http://${_server.address.host}:${_server.port}';

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      final body = await _collect(request);
      requests.add(
        _RecordedRequest(
          request.method,
          request.uri.path,
          request.headers.value(HttpHeaders.authorizationHeader),
          body,
        ),
      );
      final index = responses.indexWhere(
        (item) => item.method == request.method,
      );
      if (index != -1) {
        final scripted = responses.removeAt(index);
        request.response.statusCode = scripted.status;
        scripted.headers.forEach(request.response.headers.set);
        await request.response.close();
        continue;
      }
      await _respond(request, body);
    }
  }

  Future<List<int>> _collect(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<void> _respond(HttpRequest request, List<int> body) async {
    final response = request.response;
    final path = request.uri.path;
    switch (request.method) {
      case 'OPTIONS':
        response.headers.set('dav', '1,2');
        response.statusCode = HttpStatus.ok;
      case 'MKCOL':
        response.statusCode = files.containsKey(path)
            ? HttpStatus.methodNotAllowed
            : HttpStatus.created;
        files.putIfAbsent(path, () => const []);
      case 'PUT':
        files[path] = body;
        response.statusCode = HttpStatus.created;
      case 'GET':
        final stored = files[path];
        if (stored == null) {
          response.statusCode = HttpStatus.notFound;
        } else {
          response.statusCode = HttpStatus.ok;
          response.add(stored);
        }
      case 'DELETE':
        response.statusCode = files.remove(path) == null
            ? HttpStatus.notFound
            : HttpStatus.noContent;
      case 'PROPFIND':
        response.statusCode = HttpStatus.multiStatus;
        response.headers.contentType = ContentType('application', 'xml');
        response.write('<d:multistatus xmlns:d="DAV:">');
        final prefix = path.endsWith('/') ? path : '$path/';
        for (final file in files.keys.where(
          (name) =>
              name.startsWith(prefix) &&
              name.length > prefix.length &&
              !name.substring(prefix.length).contains('/'),
        )) {
          final href = htmlEscape.convert(Uri(path: file).toString());
          response.write(
            '<d:response><d:href>$href</d:href><d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>',
          );
        }
        response.write('</d:multistatus>');
      default:
        response.statusCode = HttpStatus.methodNotAllowed;
    }
    await response.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const firstProps = DAVProps(
    uri: 'https://dav.example.com',
    user: 'first',
    password: 'first-password',
  );
  const secondProps = DAVProps(
    uri: 'https://dav.example.com',
    user: 'second',
    password: 'second-password',
  );

  test('latest DAV connectivity check wins', () async {
    final firstResult = Completer<bool>();
    final secondResult = Completer<bool>();
    final results = [firstResult.future, secondResult.future];
    var index = 0;
    final controller = DAVConnectionController(
      createClient: (props) {
        return _FakeDAVClient(props, results[index++]);
      },
    );
    addTearDown(controller.dispose);

    final firstUpdate = controller.update(firstProps);
    final secondUpdate = controller.update(secondProps);

    secondResult.complete(true);
    await secondUpdate;
    expect(controller.value, isTrue);

    firstResult.complete(false);
    await firstUpdate;
    expect(controller.value, isTrue);
  });

  test('changing only the remote file name does not ping again', () async {
    var pingCount = 0;
    final controller = DAVConnectionController(
      createClient: (props) {
        return _FakeDAVClient(props, Future.value(true), () => pingCount++);
      },
    );
    addTearDown(controller.dispose);

    await controller.update(firstProps);
    await controller.update(firstProps.copyWith(fileName: 'another.zip'));

    expect(pingCount, 1);
    expect(controller.value, isTrue);
    expect(controller.client?.fileName, 'another.zip');
  });

  test('new credentials reset connectivity while ping is pending', () async {
    final result = Completer<bool>();
    final controller = DAVConnectionController(
      createClient: (props) {
        return _FakeDAVClient(props, result.future);
      },
    );
    addTearDown(controller.dispose);

    final update = controller.update(firstProps);

    expect(controller.value, isNull);
    result.complete(true);
    await update;
    expect(controller.value, isTrue);
  });

  group('against a live server', () {
    late _TestServer server;
    late Directory root;
    HttpOverrides? testOverrides;

    setUpAll(() async {
      root = Directory.systemTemp.createTempSync('dav_client_test');
      await useAppPaths(root);
    });

    tearDownAll(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      // The widget test binding installs an override that answers every
      // request with 400 instead of opening a socket.
      testOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      server = await _TestServer.start();
    });

    tearDown(() async {
      HttpOverrides.global = testOverrides;
      await server.close();
    });

    DAVClient buildClient({String path = ''}) {
      return DAVClient(
        DAVProps(
          uri: '${server.uri}$path',
          user: 'user',
          password: 'secret',
          fileName: 'backup.zip',
        ),
      );
    }

    File writeArchive(List<int> bytes) {
      return File(join(root.path, 'source.zip'))..writeAsBytesSync(bytes);
    }

    test('ping reports a server that answers OPTIONS', () async {
      expect(await buildClient().ping(), isTrue);
      expect(server.requests.single.method, 'OPTIONS');
    });

    test('ping reports a server that refuses the credentials', () async {
      server.responses.add((
        method: 'OPTIONS',
        status: HttpStatus.unauthorized,
        headers: const {},
      ));

      expect(await buildClient().ping(), isFalse);
    });

    test('upload creates the collection and puts the archive', () async {
      final archive = writeArchive(List<int>.generate(32, (index) => index));

      await buildClient().upload(archive.path);

      expect(server.requests.map((item) => item.method), ['MKCOL', 'PUT']);
      expect(server.requests.last.path, '/$appName/backup.zip');
      expect(server.files['/$appName/backup.zip'], archive.readAsBytesSync());
    });

    test(
      'versioned backups preserve legacy files and can restore a chosen version',
      () async {
        final client = buildClient();
        server.files['/$appName/backup.zip'] = [9];
        server.files['/$appName/unrelated.zip'] = [8];
        await client.uploadVersion(writeArchive([1, 2, 3]).path);
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await client.uploadVersion(writeArchive([4, 5, 6]).path);
        final backups = await client.listBackups();
        expect(backups, hasLength(3));
        expect(backups.last.name, 'backup.zip');
        expect(backups.first.createdAt, isNotNull);
        expect(server.files['/$appName/backup.zip'], [9]);
        final restored = join(root.path, 'older-backup.zip');
        await client.downloadVersion(restored, backups[1].name);
        expect(File(restored).readAsBytesSync(), [1, 2, 3]);
        expect(
          server.requests.every((request) => request.method != 'DELETE'),
          isTrue,
        );
      },
    );

    test(
      'missing backup directory is empty but authentication errors propagate',
      () async {
        server.responses.add((
          method: 'PROPFIND',
          status: HttpStatus.notFound,
          headers: const {},
        ));
        expect(await buildClient().listBackups(), isEmpty);
        server.responses.add((
          method: 'PROPFIND',
          status: HttpStatus.forbidden,
          headers: const {},
        ));
        await expectLater(
          buildClient().listBackups(),
          throwsA(isA<DAVException>()),
        );
      },
    );

    test(
      'notes round trip through sidecars without altering old archives',
      () async {
        final client = buildClient();
        server.files['/$appName/backup.zip'] = [9];
        await client.uploadVersion(writeArchive([1, 2, 3]).path);
        final latest = (await client.listBackups()).first;
        await client.saveNote(latest.name, 'Before travel');

        final reader = buildClient();
        final metadata = await reader.listBackups();
        expect(metadata.first.note, isEmpty);
        final refreshed = await Future.wait(metadata.map(reader.readNote));
        expect(refreshed.first.note, 'Before travel');
        final reads = server.requests.where((r) => r.method == 'GET').length;
        expect((await reader.readNote(metadata.first)).note, 'Before travel');
        expect(server.requests.where((r) => r.method == 'GET').length, reads);
        expect(refreshed.last.name, 'backup.zip');
        expect(refreshed.last.note, isEmpty);
        expect(server.files['/$appName/${latest.name}'], [1, 2, 3]);
        expect(server.files['/$appName/backup.zip'], [9]);

        await client.saveNote(latest.name, '');
        expect((await client.listBackups()).first.note, isEmpty);
        expect(server.files.containsKey('/$appName/${latest.name}'), isTrue);
      },
    );

    test(
      'invalid optional notes do not hide a restorable legacy backup',
      () async {
        server.files['/$appName/backup.zip'] = [9];
        server.files['/$appName/backup.zip.note.json'] = utf8.encode(
          'invalid JSON',
        );
        final reader = buildClient();
        final backups = await reader.listBackups();
        expect((await reader.readNote(backups.single)).note, isEmpty);
        expect(backups.single.name, 'backup.zip');
        expect(backups.single.note, isEmpty);
      },
    );

    test(
      'manual deletion removes only the chosen archive and its note',
      () async {
        final client = buildClient();
        server.files['/$appName/backup.zip'] = [9];
        await client.uploadVersion(writeArchive([1]).path);
        final latest = (await client.listBackups()).first;
        await client.saveNote(latest.name, 'Disposable');
        await client.deleteVersion(latest.name);
        expect((await client.listBackups()).single.name, 'backup.zip');
        expect(
          server.files.containsKey('/$appName/${latest.name}.note.json'),
          isFalse,
        );
        await expectLater(
          client.deleteVersion('../backup.zip'),
          throwsFormatException,
        );
        await expectLater(
          client.saveNote('../backup.zip', 'unsafe'),
          throwsFormatException,
        );
        expect(server.files['/$appName/backup.zip'], [9]);
      },
    );

    test('selected version cannot escape its backup directory', () async {
      await expectLater(
        buildClient().downloadVersion(
          join(root.path, 'target.zip'),
          '../backup.zip',
        ),
        throwsFormatException,
      );
      expect(server.requests, isEmpty);
    });

    test('a base path prefixes every request', () async {
      await buildClient(path: '/remote.php/dav').ping();

      expect(server.requests.single.path, '/remote.php/dav/');
    });

    test('an existing collection is not an error', () async {
      final archive = writeArchive(const [1, 2, 3]);
      final client = buildClient();

      await client.upload(archive.path);

      await expectLater(client.upload(archive.path), completes);
    });

    test('download writes the remote archive to the given path', () async {
      final payload = List<int>.generate(64, (index) => index);
      server.files['/$appName/backup.zip'] = payload;
      final target = join(root.path, 'download.zip');

      await buildClient().download(target);

      expect(File(target).readAsBytesSync(), payload);
    });

    test('download reports the status the server sent', () async {
      await expectLater(
        buildClient().download(join(root.path, 'missing.zip')),
        throwsA(
          isA<DAVException>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('GET'), contains('404')),
          ),
        ),
      );
    });

    test('a redirected download keeps the method', () async {
      final payload = List<int>.generate(8, (index) => index);
      server.files['/moved/backup.zip'] = payload;
      server.responses.add((
        method: 'GET',
        status: HttpStatus.movedPermanently,
        headers: const {'location': '/moved/backup.zip'},
      ));

      await buildClient().download(join(root.path, 'moved.zip'));

      expect(server.requests.map((item) => item.method), ['GET', 'GET']);
      expect(File(join(root.path, 'moved.zip')).readAsBytesSync(), payload);
    });

    test('credentials are sent as basic auth', () async {
      await buildClient().ping();

      expect(
        server.requests.single.authorization,
        'Basic ${base64.encode(utf8.encode('user:secret'))}',
      );
    });

    test('a digest challenge is answered and retried once', () async {
      server.responses.add((
        method: 'OPTIONS',
        status: HttpStatus.unauthorized,
        headers: const {
          'www-authenticate':
              'Digest realm="dav", qop="auth", nonce="abc123", opaque="op"',
        },
      ));

      expect(await buildClient().ping(), isTrue);

      expect(server.requests, hasLength(2));
      expect(server.requests.first.authorization, startsWith('Basic '));
      final retry = server.requests.last.authorization!;
      expect(retry, startsWith('Digest '));
      expect(retry, contains('username="user"'));
      expect(retry, contains('nonce="abc123"'));
      expect(retry, contains('qop=auth'));
      expect(retry, contains('nc=00000001'));
    });

    test('anonymous access sends no authorization header', () async {
      await DAVClient(DAVProps(uri: server.uri, user: '', password: '')).ping();

      expect(server.requests.single.authorization, isNull);
    });
  });
}
