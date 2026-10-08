import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/money_movement.dart';

class MovementRepository {
  MovementRepository._(this._file) : _memory = null;

  MovementRepository.inMemory() : _file = null, _memory = <MoneyMovement>[];

  static const _dataChannel = MethodChannel('com.bruges.finanzas360/data');
  static const _uuid = Uuid();

  final File? _file;
  final List<MoneyMovement>? _memory;
  Future<void> _writeTail = Future<void>.value();

  Directory? get dataDirectory => _file?.parent;

  static Future<MovementRepository> open(Directory directory) async {
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'movements.json'));
    final backup = File('${file.path}.bak');
    if (!await file.exists() && await backup.exists()) {
      await backup.rename(file.path);
    }
    if (!await file.exists()) {
      await file.writeAsString(jsonEncode({'version': 2, 'movements': []}));
    }
    return MovementRepository._(file);
  }

  static Future<MovementRepository> openForCurrentPlatform() async {
    final Directory directory;
    if (Platform.isWindows) {
      final appData = Platform.environment['LOCALAPPDATA'];
      if (appData == null || appData.isEmpty) {
        throw StateError('Windows no informó la carpeta de datos del usuario.');
      }
      directory = Directory(p.join(appData, 'Bruges', 'Finanzas360'));
    } else if (Platform.isAndroid) {
      final appData = await _dataChannel.invokeMethod<String>('dataDirectory');
      if (appData == null || appData.isEmpty) {
        throw StateError(
          'Android no informó la carpeta privada de la aplicación.',
        );
      }
      directory = Directory(appData);
    } else {
      throw UnsupportedError(
        'Almacenamiento local aún no configurado para este sistema.',
      );
    }
    return open(directory);
  }

  String createId() => _uuid.v4();

  Future<List<MoneyMovement>> listMovements() {
    return _serialize(() async {
      if (_memory case final memory?) {
        final rows = [...memory]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return rows;
      }
      final data = await _readData();
      final rows = (data['movements']! as List<Object?>)
          .map((row) => MoneyMovement.fromJson(row! as Map<String, Object?>))
          .toList();
      rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rows;
    });
  }

  Future<bool> addMovement(MoneyMovement movement) {
    return _serialize(() async {
      if (_memory case final memory?) {
        if (memory.any((row) => row.id == movement.id)) return false;
        memory.add(movement);
        return true;
      }
      final data = await _readData();
      final rows = data['movements']! as List<Object?>;
      final exists = rows.any(
        (row) => (row! as Map<String, Object?>)['id'] == movement.id,
      );
      if (exists) return false;
      rows.add(movement.toJson());
      await _writeData(data);
      return true;
    });
  }

  Future<Map<String, Object?>> _readData() async {
    try {
      final decoded =
          jsonDecode(await _file!.readAsString()) as Map<String, Object?>;
      if (decoded['movements'] is! List<Object?>) {
        throw const FormatException(
          'El archivo de movimientos no tiene un formato compatible.',
        );
      }
      if (decoded['version'] == 1) {
        final migratedRows = (decoded['movements']! as List<Object?>).map((
          row,
        ) {
          return MoneyMovement.fromJson(row! as Map<String, Object?>).toJson();
        }).toList();
        final migrated = <String, Object?>{
          ...decoded,
          'version': 2,
          'movements': migratedRows,
        };
        await _writeData(migrated);
        return migrated;
      }
      if (decoded['version'] == 2) return decoded;
      throw const FormatException(
        'El archivo de movimientos tiene una versión no compatible.',
      );
    } catch (_) {
      final recovered = await _readValidBackup();
      if (recovered == null) rethrow;
      await _writeData(recovered);
      return recovered;
    }
  }

  Future<Map<String, Object?>?> _readValidBackup() async {
    final backup = File('${_file!.path}.bak');
    if (!await backup.exists()) return null;
    try {
      final recovered =
          jsonDecode(await backup.readAsString()) as Map<String, Object?>;
      if (recovered['version'] != 2 || recovered['movements'] is! List) {
        return null;
      }
      for (final row in recovered['movements']! as List<Object?>) {
        MoneyMovement.fromJson(row! as Map<String, Object?>);
      }
      return recovered;
    } on Object {
      return null;
    }
  }

  Future<void> _writeData(Map<String, Object?> data) async {
    final file = _file!;
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temp.writeAsString(jsonEncode({...data, 'version': 2}), flush: true);
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await temp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _writeTail = _writeTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }
}
