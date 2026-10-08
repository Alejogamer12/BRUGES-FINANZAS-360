import 'dart:convert';
import 'dart:io';

import '../domain/money_movement.dart';

class MovementExportService {
  static String toCsv(Iterable<MoneyMovement> movements) {
    final rows = <List<String>>[
      [
        'id',
        'type',
        'amountMinor',
        'currency',
        'category',
        'note',
        'createdAtUtc',
        'syncState',
        'origin',
        'verification',
        'sourceName',
        'counterparty',
        'reference',
        'method',
        'reportedStatus',
      ],
      for (final movement in movements)
        [
          movement.id,
          movement.kind.name,
          movement.amountMinor.toString(),
          movement.currency,
          movement.category,
          movement.note,
          movement.createdAt.toUtc().toIso8601String(),
          movement.syncState.name,
          movement.origin.name,
          movement.verification.name,
          movement.sourceName ?? '',
          movement.counterparty ?? '',
          movement.reference ?? '',
          movement.method ?? '',
          movement.reportedStatus ?? '',
        ],
    ];
    return rows.map((row) => row.map(_escapeCsv).join(',')).join('\r\n');
  }

  static String toJson(Iterable<MoneyMovement> movements) =>
      const JsonEncoder.withIndent('  ')
          .convert(movements.map((movement) => movement.toJson()).toList());

  static Future<File> writeCsv(
    Iterable<MoneyMovement> movements,
    Directory directory,
  ) => _write('csv', toCsv(movements), directory);

  static Future<File> writeJson(
    Iterable<MoneyMovement> movements,
    Directory directory,
  ) => _write('json', toJson(movements), directory);

  static Future<File> _write(
    String extension,
    String contents,
    Directory directory,
  ) async {
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${fileName(extension)}',
    );
    await file.writeAsString(contents, flush: true);
    return file;
  }

  static String fileName(String extension) {
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    return 'BRUGES-FINANZAS-360-$timestamp.$extension';
  }

  static String _escapeCsv(String value) => '"${value.replaceAll('"', '""')}"';
}
