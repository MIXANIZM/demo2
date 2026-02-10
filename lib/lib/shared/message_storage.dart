import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Хранилище сообщений (пока локально в JSON).
/// Позже заменим на SQLite/Drift без изменения UI.
class MessageStorage {
  MessageStorage._();

  static final MessageStorage instance = MessageStorage._();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'messages.json'));
  }

  Future<Map<String, dynamic>?> read() async {
    final f = await _file();
    if (!await f.exists()) return null;
    try {
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
