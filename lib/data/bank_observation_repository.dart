import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../services/bank_notification_parser.dart';

class BankObservationRepository {
  BankObservationRepository._(this._file) : _memory = null;

  BankObservationRepository.inMemory()
    : _file = null,
      _memory = <BankNotificationObservation>[];

  final File? _file;
  final List<BankNotificationObservation>? _memory;
  Future<void> _writeTail = Future<void>.value();

  static Future<BankObservationRepository> open(Directory directory) async {
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'bank-observations.json'));
    if (!await file.exists()) {
      await file.writeAsString(jsonEncode({'version': 1, 'observations': []}));
    }
    return BankObservationRepository._(file);
  }

  Future<List<BankNotificationObservation>> listPending() async {
    return _serialize(() async {
      final observations = await _read();
      return observations.where((row) => row.reviewState == 'review').toList()
        ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    });
  }

  Future<bool> add(BankNotificationObservation observation) =>
      _serialize(() async {
        final observations = await _read();
        if (observations.any((row) => row.id == observation.id)) return false;
        observations.add(observation);
        await _write(observations);
        return true;
      });

  Future<void> markReviewed(String id, {required bool accepted}) =>
      _serialize(() async {
        final observations = await _read();
        final index = observations.indexWhere((row) => row.id == id);
        if (index == -1) throw StateError('No se encontró la observación.');
        observations[index] = observations[index].reviewed(accepted: accepted);
        await _write(observations);
      });

  Future<List<BankNotificationObservation>> _read() async {
    if (_memory case final memory?) return [...memory];
    final decoded =
        jsonDecode(await _file!.readAsString()) as Map<String, Object?>;
    if (decoded['version'] != 1 || decoded['observations'] is! List) {
      throw const FormatException(
        'La bandeja de observaciones no es compatible.',
      );
    }
    return (decoded['observations']! as List<Object?>)
        .map(
          (row) => BankNotificationObservation.fromJson(
            row! as Map<String, Object?>,
          ),
        )
        .toList();
  }

  Future<void> _write(List<BankNotificationObservation> observations) async {
    if (_memory case final memory?) {
      memory
        ..clear()
        ..addAll(observations);
      return;
    }
    final file = _file!;
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temp.writeAsString(
      jsonEncode({
        'version': 1,
        'observations': observations.map((row) => row.toJson()).toList(),
      }),
      flush: true,
    );
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
