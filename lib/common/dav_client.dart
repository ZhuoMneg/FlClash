import 'dart:async';
import 'dart:io' as io;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';

typedef DAVClientFactory = DAVClient Function(DAVProps props);

class DAVBackup {
  const DAVBackup({required this.name, this.createdAt});

  final String name;
  final DateTime? createdAt;
}

class DAVClient {
  DAVClient(DAVProps dav)
    : _transport = DAVTransport(
        uri: dav.uri,
        user: dav.user,
        password: dav.password,
      ),
      fileName = dav.fileName;

  final DAVTransport _transport;
  final String fileName;

  Future<bool> ping() async {
    try {
      await _transport.options('/');
      return true;
    } catch (e) {
      commonPrint.log(
        'dav ping error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
  }

  String get root => '/$appName';

  String get backupFile => '$root/$fileName';

  Future<void> upload(String localPath) async {
    await _transport.mkcol(root);
    await _transport.put(backupFile, await io.File(localPath).readAsBytes());
  }

  Future<void> download(String localPath) async {
    final bytes = await _transport.get(backupFile);
    await io.File(localPath).safeWriteAsBytes(bytes);
  }

  String get _baseName => fileName.toLowerCase().endsWith('.zip')
      ? fileName.substring(0, fileName.length - 4)
      : fileName;

  bool _isFileName(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      !name.contains('/') &&
      !name.contains('\\') &&
      !name.contains('\u0000');

  late final _versionPattern = RegExp(
    '^${RegExp.escape(_baseName)}_(\\d+)_[a-f0-9]{8}\\.zip\$',
  );

  DAVBackup? _backupOf(String name) {
    if (!_isFileName(name)) return null;
    if (name == fileName) return DAVBackup(name: name);
    final match = _versionPattern.firstMatch(name);
    final stamp = match == null ? null : int.tryParse(match[1]!);
    if (stamp == null) return null;
    try {
      return DAVBackup(
        name: name,
        createdAt: DateTime.fromMicrosecondsSinceEpoch(stamp, isUtc: true),
      );
    } on RangeError {
      return null;
    }
  }

  Future<void> uploadVersion(String localPath) async {
    if (!_isFileName(fileName)) {
      throw const FormatException('Invalid backup file name');
    }
    final name =
        '${_baseName}_${DateTime.now().microsecondsSinceEpoch}_${uuidV4.substring(0, 8)}.zip';
    await _transport.mkcol(root);
    await _transport.put('$root/$name', await io.File(localPath).readAsBytes());
  }

  Future<List<DAVBackup>> listBackups() async {
    final List<String> names;
    try {
      names = await _transport.listFiles(root);
    } on DAVException catch (error) {
      if (error.statusCode == 404) return [];
      rethrow;
    }
    final backups = names.map(_backupOf).nonNulls.toList();
    backups.sort((a, b) {
      final stamp = (b.createdAt?.microsecondsSinceEpoch ?? -1).compareTo(
        a.createdAt?.microsecondsSinceEpoch ?? -1,
      );
      return stamp != 0 ? stamp : b.name.compareTo(a.name);
    });
    return backups;
  }

  Future<void> downloadVersion(String localPath, String name) async {
    if (_backupOf(name) == null) {
      throw const FormatException('Invalid backup file name');
    }
    final bytes = await _transport.get('$root/$name');
    await io.File(localPath).safeWriteAsBytes(bytes);
  }
}

class DAVConnectionController extends ValueNotifier<bool?> {
  DAVConnectionController({DAVClientFactory? createClient})
    : _createClient = createClient ?? DAVClient.new,
      super(null);

  final DAVClientFactory _createClient;

  DAVProps? _lastProps;
  bool _hasUpdated = false;
  int _requestId = 0;
  bool _disposed = false;

  DAVClient? client;

  Future<void> update(DAVProps? props) async {
    final nextClient = props == null ? null : _createClient(props);
    client = nextClient;

    final rawProps = props?.copyWith(fileName: '');
    final rawLastProps = _lastProps?.copyWith(fileName: '');
    final isSameCredentials = _hasUpdated && rawProps == rawLastProps;
    _lastProps = props;
    _hasUpdated = true;
    if (isSameCredentials) {
      return;
    }

    final requestId = ++_requestId;
    value = null;
    final result = await nextClient?.ping() ?? false;
    if (!_disposed && requestId == _requestId) {
      value = result;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _requestId++;
    super.dispose();
  }
}
