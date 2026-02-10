import 'dart:async';
import 'package:flutter/foundation.dart';
import 'task_models.dart';
import 'task_storage.dart';

class TaskStore extends ChangeNotifier {
  TaskStore._();
  static final TaskStore instance = TaskStore._();

  final List<TaskItem> _tasks = [];
  final List<String> _folders = ['Входящие', 'Покупки', 'Доставка', 'Архив'];

  String? _activeFolder;
  bool _loaded = false;
  Timer? _saveDebounce;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final loaded = await TaskStorage.loadTasks();
    _tasks
      ..clear()
      ..addAll(loaded);
    _loaded = true;
    notifyListeners();
  }

  List<TaskItem> get visibleTasks {
    Iterable<TaskItem> list = _tasks;
    if (_activeFolder != null) {
      list = list.where((t) => t.folder == _activeFolder);
    } else {
      list = list.where((t) => t.folder != 'Архив');
    }
    return list.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void addTask(String text) {
    if (text.trim().isEmpty) return;
    final task = TaskItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text.trim(),
      createdAt: DateTime.now(),
      status: TaskStatus.todo,
      isStriked: false,
      folder: _activeFolder ?? 'Входящие',
    );
    _tasks.insert(0, task);
    notifyListeners();
    _scheduleSave();
  }

  void toggleStatus(String id) {
    final t = _tasks.firstWhere((e) => e.id == id);
    t.status = t.status.next();
    notifyListeners();
    _scheduleSave();
  }

  void toggleStrike(String id) {
    final t = _tasks.firstWhere((e) => e.id == id);
    t.isStriked = !t.isStriked;
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), () {
      TaskStorage.saveTasks(_tasks);
    });
  }
}
