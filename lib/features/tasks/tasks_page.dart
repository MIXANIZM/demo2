import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../shared/task_models.dart';

class _FolderItem {
  final String id;
  String name;
  _FolderItem({required this.id, required this.name});
}

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();

  // null = показываем ВСЕ задачи (по умолчанию)
  String? _selectedFolderId;

  // Папки (без "Все"!)
  final List<_FolderItem> _folders = [
    _FolderItem(id: 'inbox', name: 'Входящие'),
    _FolderItem(id: 'buy', name: 'Покупки'),
    _FolderItem(id: 'delivery', name: 'Доставка'),
  ];

  // Архив как “особое состояние”
  bool _archiveView = false;
  final Set<String> _archivedTaskIds = {};

  // --- persistence ---
  bool _loadedFromDisk = false;
  bool _pendingSave = false;
  bool _editedBeforeLoad = false;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // грузим сохраненные задачи/папки
    unawaited(_loadFromDisk());
  }

    @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // На фоне/закрытие — сохраняем немедленно, чтобы не потерять изменения.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_saveNow());
    }
  }

@override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Попытка сохранить прямо перед закрытием экрана.
    unawaited(_saveNow());
    _saveDebounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  final List<TaskItem> _tasks = [
    TaskItem(
      id: 't1',
      text: 'Отправить трек клиенту (Яндекс)',
      createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
      status: TaskStatus.done,
      isStriked: false,
      folder: '',
    ),
    TaskItem(
      id: 't2',
      text: 'Купить упаковку и скотч',
      createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
      status: TaskStatus.doing,
      isStriked: false,
      folder: '',
    ),
    TaskItem(
      id: 't3',
      text: 'Позвонить клиенту по заказу #123',
      createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      status: TaskStatus.todo,
      isStriked: false,
      folder: '',
    ),
  ];

  /// Вызывается из общего AppBar (HomeShell) — открывает создание папки.
  void openCreateFolderDialog() => _createFolder();

  @override
  Widget build(BuildContext context) {
    final visible = _filteredTasks();

    return Column(
      children: [
        // ТАБЫ (без "+" внутри — кнопка теперь в общем AppBar)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: _buildFolderGridTabs(),
        ),

        const SizedBox(height: 6),

        // список задач
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: visible.length,
            itemBuilder: (_, i) => _buildTaskTile(visible[i]),
          ),
        ),

        // инпут создания
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Вложение (пока заглушка)',
                  icon: const Icon(Icons.attach_file),
                  onPressed: _attachmentsStub,
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: InputDecoration(
                      hintText: 'Написать задачу...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (_) => _addTask(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _addTask,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------- Tabs ----------

  Widget _buildFolderGridTabs() {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        const spacing = 8.0;

        // 3 колонки на телефон (чтобы “на всю ширину”)
        final cols = maxW >= 420 ? 4 : 3;
        final itemW = (maxW - spacing * (cols - 1)) / cols;

        final items = <Widget>[
          // Архив — отдельный таб
          SizedBox(
            width: itemW,
            child: _FolderChip(
              text: 'Архив',
              selected: _archiveView,
              dotColor: const Color(0xFF90A4AE),
              onTap: () {
                setState(() {
                  _archiveView = !_archiveView;
                  if (_archiveView) _selectedFolderId = null;
                });
    _scheduleSave();
              },
              onLongPress: null,
            ),
          ),

          ..._folders.map((f) {
            final selected = (!_archiveView && _selectedFolderId == f.id);
            return SizedBox(
              width: itemW,
              child: _FolderChip(
                text: f.name,
                selected: selected,
                dotColor: Colors.black26,
                onTap: () {
                  setState(() {
                    _archiveView = false;
                    // повторный тап снимает фильтр (показываем все)
                    if (_selectedFolderId == f.id) {
                      _selectedFolderId = null;
                    } else {
                      _selectedFolderId = f.id;
                    }
                  });
    _scheduleSave();
                },
                onLongPress: () => _editFolder(f),
              ),
            );
          }).toList(),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: 8,
          children: items,
        );
      },
    );
  }

  // ---------- Tasks UI ----------

  Widget _buildTaskTile(TaskItem t) {
    final style = _taskStyle(t);
    final time = _fmtTime(t.createdAt);

    return GestureDetector(
      onTap: () => _cycleStatus(t), // обычный тап = смена статуса
      onLongPress: () => _openTaskMenu(t), // долгий тап = меню
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: style.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: style.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: style.text,
                decoration:
                    t.isStriked ? TextDecoration.lineThrough : TextDecoration.none,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              time,
              style: TextStyle(
                fontSize: 12,
                color: style.text.withOpacity(0.75),
                decoration:
                    t.isStriked ? TextDecoration.lineThrough : TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _cycleStatus(TaskItem t) {
    setState(() {
      t.status = t.status.next();
    });
    _scheduleSave();
  }

  // ---------- Filtering ----------

  Future<File> _tasksFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'tasks_state_v1.json'));
  }

  void _scheduleSave() {
    if (!_loadedFromDisk) {
      _pendingSave = true;
      _editedBeforeLoad = true;
      return;
    }
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      _saveNow();
    });
  }

  Future<void> _saveNow() async {
    try {
      final f = await _tasksFile();
      final data = <String, dynamic>{
        'v': 1,
        'selectedFolderId': _selectedFolderId,
        'archiveView': _archiveView,
        'archived': _archivedTaskIds.toList(),
        'folders': _folders.map((x) => {'id': x.id, 'name': x.name}).toList(),
        'tasks': _tasks.map((t) => {
              'id': t.id,
              'text': t.text,
              'createdAtMs': t.createdAt.millisecondsSinceEpoch,
              'status': t.status.name,
              'isStriked': t.isStriked,
              'folder': t.folder,
            }).toList(),
      };
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
    } catch (_) {
      // игнорируем: это прототип
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final f = await _tasksFile();
      if (!await f.exists()) {
        _loadedFromDisk = true;
        // первая инициализация: сохраняем дефолты, чтобы дальше было стабильно
        unawaited(_saveNow());
        return;
      }
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _loadedFromDisk = true;
        return;
      }
      final map = decoded.cast<String, dynamic>();

      final folders = (map['folders'] as List?)?.cast<dynamic>() ?? const [];
      final tasks = (map['tasks'] as List?)?.cast<dynamic>() ?? const [];
      final archived = (map['archived'] as List?)?.cast<dynamic>() ?? const [];

      setState(() {
        final loadedFolders = folders.map((e) {
          final m = (e as Map).cast<String, dynamic>();
          return _FolderItem(id: (m['id'] ?? '').toString(), name: (m['name'] ?? '').toString());
        }).where((x) => x.id.isNotEmpty).toList(growable: false);

        final loadedTasks = tasks.map((e) {
          final m = (e as Map).cast<String, dynamic>();
          final statusName = (m['status'] ?? 'todo').toString();
          final status = TaskStatus.values.firstWhere(
            (s) => s.name == statusName,
            orElse: () => TaskStatus.todo,
          );
          return TaskItem(
            id: (m['id'] ?? '').toString(),
            text: (m['text'] ?? '').toString(),
            createdAt: DateTime.fromMillisecondsSinceEpoch((m['createdAtMs'] ?? 0) as int),
            status: status,
            isStriked: (m['isStriked'] ?? false) as bool,
            folder: (m['folder'] ?? '').toString(),
          );
        }).where((t) => t.id.isNotEmpty).toList(growable: false);

        final loadedArchived = archived.map((x) => x.toString()).toList(growable: false);

        if (_editedBeforeLoad) {
          // Пользователь уже успел что-то изменить, пока шла загрузка.
          // Поэтому НЕ перезатираем текущий стейт "с диска", а аккуратно мерджим:
          // добавляем то, чего у нас ещё нет.
          final folderIds = _folders.map((x) => x.id).toSet();
          for (final f in loadedFolders) {
            if (!folderIds.contains(f.id)) _folders.add(f);
          }

          final taskIds = _tasks.map((x) => x.id).toSet();
          for (final t in loadedTasks) {
            if (!taskIds.contains(t.id)) _tasks.add(t);
          }

          for (final a in loadedArchived) {
            if (!_archivedTaskIds.contains(a)) _archivedTaskIds.add(a);
          }

          // Флаги вида оставляем как есть (то, что уже выбрал пользователь).
        } else {
          // Обычная загрузка: применяем полностью.
          _folders
            ..clear()
            ..addAll(loadedFolders);

          _tasks
            ..clear()
            ..addAll(loadedTasks);

          _archivedTaskIds
            ..clear()
            ..addAll(loadedArchived);

          _archiveView = (map['archiveView'] ?? false) as bool;
          _selectedFolderId = (map['selectedFolderId'] as String?);
        }
      });
      _scheduleSave();
    } catch (_) {
      // игнорируем
    } finally {
      _loadedFromDisk = true;
      if (_pendingSave) {
        _pendingSave = false;
        _scheduleSave();
      }
    }
  }

  List<TaskItem> _filteredTasks() {
    final list = _tasks.where((t) {
      final isArchived = _archivedTaskIds.contains(t.id);
      if (_archiveView) return isArchived;
      if (isArchived) return false; // архив скрываем, если не в архиве
      if (_selectedFolderId == null) return true; // все
      return t.folder == _selectedFolderId;
    }).toList();

    // новые сверху
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  // ---------- Add / Menu ----------

  void _addTask() {
    final text = _input.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _tasks.add(
        TaskItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: text,
          createdAt: DateTime.now(),
          status: TaskStatus.todo,
          isStriked: false,
          folder: _archiveView ? '' : (_selectedFolderId ?? ''),
        ),
      );
      _input.clear();
    });
    _scheduleSave();
  }

  void _attachmentsStub() async {
    // пока без пакетов для выбора файлов — заглушка
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Фото (заглушка)'),
              onTap: () => Navigator.pop(context, 'Фото'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Видео (заглушка)'),
              onTap: () => Navigator.pop(context, 'Видео'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('Файл (заглушка)'),
              onTap: () => Navigator.pop(context, 'Файл'),
            ),
          ],
        ),
      ),
    );

    if (type == null) return;

    setState(() {
      _tasks.add(
        TaskItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: '📎 $type',
          createdAt: DateTime.now(),
          status: TaskStatus.todo,
          isStriked: false,
          folder: _archiveView ? '' : (_selectedFolderId ?? ''),
        ),
      );
    });
    _scheduleSave();
  }

  void _openTaskMenu(TaskItem t) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_move),
              title: const Text('Переместить в папку'),
              onTap: () async {
                Navigator.pop(context);
                await _moveTaskFullScreen(t);
              },
            ),
            // "Зачеркнуть" — НЕ ТРОГАЕМ (по твоему указанию)
            ListTile(
              leading: Icon(
                t.isStriked ? Icons.format_strikethrough : Icons.format_strikethrough,
              ),
              title: Text(t.isStriked ? 'Снять зачёркивание' : 'Зачеркнуть'),
              onTap: () {
                Navigator.pop(context);
                setState(() => t.isStriked = !t.isStriked);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(_archivedTaskIds.contains(t.id) ? 'Убрать из архива' : 'В архив'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  if (_archivedTaskIds.contains(t.id)) {
                    _archivedTaskIds.remove(t.id);
                  } else {
                    _archivedTaskIds.add(t.id);
                  }
                });
    _scheduleSave();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _archivedTaskIds.remove(t.id);
                  _tasks.removeWhere((x) => x.id == t.id);
                });
    _scheduleSave();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveTaskFullScreen(TaskItem t) async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => _MoveTaskPage(
          folders: _folders,
          currentFolderId: t.folder.isEmpty ? null : t.folder,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      t.folder = result.isEmpty ? '' : result;
      // если переносим — выводим из архива
      _archivedTaskIds.remove(t.id);
      _archiveView = false;
    });
    _scheduleSave();
  }

  // ---------- Folders ----------

  void _createFolder() async {
    final name = await _promptText(
      title: 'Новая папка',
      hint: 'Название папки',
      initial: 'Новая папка',
    );
    if (name == null) return;

    setState(() {
      _folders.add(
        _FolderItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
        ),
      );
    });
    _scheduleSave();
  }

  void _editFolder(_FolderItem f) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.9;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: ListView(
              padding: EdgeInsets.only(bottom: 8 + MediaQuery.of(ctx).viewInsets.bottom),
              children: [
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Переименовать'),
                  onTap: () async {
                    Navigator.pop(context);
                    final name = await _promptText(
                      title: 'Переименовать папку',
                      hint: 'Название',
                      initial: f.name,
                    );
                    if (name == null) return;
                    setState(() => f.name = name);
                    _scheduleSave();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.arrow_upward),
                  title: const Text('Сдвинуть левее'),
                  onTap: () {
                    Navigator.pop(context);
                    _moveFolder(f, -1);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.arrow_downward),
                  title: const Text('Сдвинуть правее'),
                  onTap: () {
                    Navigator.pop(context);
                    _moveFolder(f, 1);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Удалить папку'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _folders.removeWhere((x) => x.id == f.id);
                      // задачи папки остаются, но без папки — снимаем привязку
                      for (final t in _tasks) {
                        if (t.folder == f.id) t.folder = '';
                      }
                      if (_selectedFolderId == f.id) _selectedFolderId = null;
                    });
    _scheduleSave();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _moveFolder(_FolderItem f, int delta) {
    final idx = _folders.indexWhere((x) => x.id == f.id);
    if (idx < 0) return;
    final newIdx = idx + delta;
    if (newIdx < 0 || newIdx >= _folders.length) return;

    setState(() {
      final item = _folders.removeAt(idx);
      _folders.insert(newIdx, item);
    });
    _scheduleSave();
  }

  // ---------- Helpers ----------

  String _fmtTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    required String initial,
  }) async {
    final ctrl = TextEditingController(text: initial);

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    return res;
  }

  _TaskStyle _taskStyle(TaskItem t) {
    // Истина по цветам/стилю — из shared/task_models.dart
    return _TaskStyle(
      bg: t.status.bubbleColor,
      border: t.status.borderColor,
      text: t.status.textColor,
    );
  }
}

class _TaskStyle {
  final Color bg;
  final Color border;
  final Color text;
  _TaskStyle({required this.bg, required this.border, required this.text});
}

class _FolderChip extends StatelessWidget {
  final String text;
  final bool selected;
  final Color dotColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FolderChip({
    required this.text,
    required this.selected,
    required this.dotColor,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Colors.black.withOpacity(0.06) : Colors.white;
    final br = selected ? Colors.black26 : Colors.black12;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: br),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Полноэкранный выбор папки для перемещения задачи
class _MoveTaskPage extends StatefulWidget {
  final List<_FolderItem> folders;
  final String? currentFolderId;

  const _MoveTaskPage({
    required this.folders,
    required this.currentFolderId,
  });

  @override
  State<_MoveTaskPage> createState() => _MoveTaskPageState();
}

class _MoveTaskPageState extends State<_MoveTaskPage> with WidgetsBindingObserver {
  String? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selected = widget.currentFolderId; // может быть null
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // На этом экране нам не надо ничего сохранять — но observer нужен,
    // чтобы не падало при addObserver/removeObserver и чтобы в будущем
    // можно было легко добавить логику.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Переместить в папку'),
        actions: [
          TextButton(
            onPressed: () {
              // пустая строка = “без папки”
              Navigator.pop(context, _selected ?? '');
            },
            child: const Text('Готово'),
          ),
        ],
      ),
      body: ListView(
        children: [
          CheckboxListTile(
            value: _selected == null,
            onChanged: (_) => setState(() => _selected = null),
            title: const Text('Без папки (видно во всех)'),
          ),
          const Divider(height: 1),
          ...widget.folders.map((f) {
            return CheckboxListTile(
              value: _selected == f.id,
              onChanged: (_) => setState(() => _selected = f.id),
              title: Text(f.name),
            );
          }),
        ],
      ),
    );
  }
}
