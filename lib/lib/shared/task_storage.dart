import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Простое хранилище задач/папок в JSON-файле.
///
/// Почему так:
/// - без новых зависимостей (shared_preferences / sqlite миграций)
/// - достаточно быстро для задач (тысячи/десятки тысяч)
/// - легко заменить позже на Drift/SQLite.
class TaskStorage {
  TaskStorage._();

  static final TaskStorage instance = TaskStorage._();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'tasks_v1.json'));
  }

  /// Читает JSON. Возвращает null если файла нет или он битый.
  Future<Map<String, dynamic>?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> data) async {
    final f = await _file();
    final raw = const JsonEncoder.withIndent('  ').convert(data);
    await f.writeAsString(raw, flush: true);
  }
}
