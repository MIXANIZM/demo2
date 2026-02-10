import 'dart:async';

import 'task_models.dart';
import 'task_storage.dart';

/// Хранит задачи/папки в памяти и сохраняет в JSON.
///
/// Это временный слой. Позже легко заменить на Drift/SQLite.
class TaskPersistStore {
  TaskPersistStore._();
  static final TaskPersistStore instance = TaskPersistStore._();

  bool _loaded = false;

  /// Папки задач.
  final List<TaskFolder> folders = [];

  /// Задачи.
  final List<TaskItem> tasks = [];

  Timer? _flushTimer;

  /// Загружает данные один раз.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    final json = await TaskStorage.instance.read();
    if (json == null) {
      _seedDefaults();
      _scheduleFlush();
      return;
    }

    try {
      final foldersJson = (json['folders'] as List?) ?? const [];
      final tasksJson = (json['tasks'] as List?) ?? const [];

      folders
        ..clear()
        ..addAll(foldersJson.whereType<Map>().map((m) => TaskFolder.fromJson(Map<String, dynamic>.from(m))));

      tasks
        ..clear()
        ..addAll(tasksJson.whereType<Map>().map((m) => TaskItem.fromJson(Map<String, dynamic>.from(m))));

      if (folders.isEmpty) {
        _seedDefaults();
      }
    } catch (_) {
      folders.clear();
      tasks.clear();
      _seedDefaults();
    }
  }

  void _seedDefaults() {
    if (folders.isNotEmpty) return;
    folders.addAll([
      TaskFolder(id: 'f_inbox', name: 'Входящие', order: 0),
      TaskFolder(id: 'f_work', name: 'Работа', order: 1),
      TaskFolder(id: 'f_personal', name: 'Личное', order: 2),
    ]);
  }

  void dispose() {
    _flushTimer?.cancel();
  }

  void markDirty() {
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    final data = <String, dynamic>{
      'version': 1,
      'folders': folders.map((f) => f.toJson()).toList(),
      'tasks': tasks.map((t) => t.toJson()).toList(),
    };
    await TaskStorage.instance.write(data);
  }
}

/// Локальный unawaited, чтобы не тянуть package:pedantic.
void unawaited(Future<void> f) {}
