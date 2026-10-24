import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';

typedef DAVClientFactory = DAVClient Function(DAVProps props);

class DAVBackup {
  const DAVBackup({required this.name, this.createdAt, this.note = ''});

  final String name;
  final DateTime? createdAt;
  final String note;

  DAVBackup withNote(String value) =>
      DAVBackup(name: name, createdAt: createdAt, note: value);
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
  Set<String> _availableNoteFiles = {};
  final _notes = <String, String>{};
  final _noteLoads = <String, Future<DAVBackup>>{};
  final _noteRevisions = <String, int>{};

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
    _availableNoteFiles = names.toSet();
    final backups = names
        .map(_backupOf)
        .nonNulls
        .map((backup) => backup.withNote(_notes[backup.name] ?? ''))
        .toList();
    backups.sort((a, b) {
      final stamp = (b.createdAt?.microsecondsSinceEpoch ?? -1).compareTo(
        a.createdAt?.microsecondsSinceEpoch ?? -1,
      );
      return stamp != 0 ? stamp : b.name.compareTo(a.name);
    });
    return backups;
  }

  Future<void> downloadVersion(String localPath, String name) async {
    _validateBackupName(name);
    final bytes = await _transport.get('$root/$name');
    await io.File(localPath).safeWriteAsBytes(bytes);
  }

  String _noteFile(String name) => '$name.note.json';

  void _validateBackupName(String name) {
    if (_backupOf(name) == null) {
      throw const FormatException('Invalid backup file name');
    }
  }

  Future<DAVBackup> readNote(DAVBackup backup) {
    _validateBackupName(backup.name);
    final cached = _notes[backup.name];
    if (cached != null) return Future.value(backup.withNote(cached));
    if (!_availableNoteFiles.contains(_noteFile(backup.name))) {
      return Future.value(backup);
    }
    return _noteLoads.putIfAbsent(backup.name, () async {
      try {
        return await _readNote(backup);
      } finally {
        final _ = _noteLoads.remove(backup.name);
      }
    });
  }

  Future<DAVBackup> _readNote(DAVBackup backup) async {
    final revision = _noteRevisions[backup.name] ?? 0;
    try {
      final bytes = await _transport.get('$root/${_noteFile(backup.name)}');
      final metadata = jsonDecode(utf8.decode(bytes));
      if (metadata is Map && metadata['note'] is String) {
        if (revision == (_noteRevisions[backup.name] ?? 0)) {
          _notes[backup.name] = metadata['note'] as String;
        }
        return backup.withNote(_notes[backup.name] ?? '');
      }
    } catch (error) {
      commonPrint.log(
        'Backup note unavailable: $error',
        logLevel: LogLevel.warning,
      );
    }
    return backup;
  }

  Future<void> saveNote(String name, String note) async {
    _validateBackupName(name);
    final path = '$root/${_noteFile(name)}';
    if (note.trim().isEmpty) {
      await _transport.delete(path);
    } else {
      await _transport.put(
        path,
        utf8.encode(jsonEncode({'version': 1, 'note': note.trim()})),
      );
    }
    _noteRevisions.update(name, (value) => value + 1, ifAbsent: () => 1);
    _notes[name] = note.trim();
    if (note.trim().isEmpty) {
      _availableNoteFiles.remove(_noteFile(name));
    } else {
      _availableNoteFiles.add(_noteFile(name));
    }
  }

  Future<void> deleteVersion(String name) async {
    _validateBackupName(name);
    await _transport.delete('$root/$name');
    _notes.remove(name);
    _availableNoteFiles.remove(_noteFile(name));
    _noteRevisions.update(name, (value) => value + 1, ifAbsent: () => 1);
    try {
      await _transport.delete('$root/${_noteFile(name)}');
    } catch (error) {
      commonPrint.log(
        'Backup note cleanup failed: $error',
        logLevel: LogLevel.warning,
      );
    }
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
