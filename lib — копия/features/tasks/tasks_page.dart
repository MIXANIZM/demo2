import 'package:flutter/material.dart';

enum TaskStatus { newTask, inProgress, done }

class _TaskItem {
  final String id;
  String text;
  DateTime createdAt;

  TaskStatus status;
  bool crossed;

  String? folderId; // null = без фильтра (видно во "всех")
  bool archived;

  _TaskItem({
    required this.id,
    required this.text,
    required this.createdAt,
    this.status = TaskStatus.newTask,
    this.crossed = false,
    this.folderId,
    this.archived = false,
  });
}

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

class _TasksPageState extends State<TasksPage> {
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

  final List<_TaskItem> _tasks = [
    _TaskItem(
      id: 't1',
      text: 'Отправить трек клиенту (Яндекс)',
      createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
      status: TaskStatus.done,
    ),
    _TaskItem(
      id: 't2',
      text: 'Купить упаковку и скотч',
      createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
      status: TaskStatus.inProgress,
    ),
    _TaskItem(
      id: 't3',
      text: 'Позвонить клиенту по заказу #123',
      createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      status: TaskStatus.newTask,
    ),
  ];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredTasks();

    return Column(
      children: [
        // ТАБЫ + "+"
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Stack(
            children: [
              _buildFolderGridTabs(),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  tooltip: 'Добавить папку',
                  icon: const Icon(Icons.add),
                  onPressed: _createFolder,
                ),
              ),
            ],
          ),
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

  Widget _buildTaskTile(_TaskItem t) {
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
                decoration: t.crossed ? TextDecoration.lineThrough : TextDecoration.none,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              time,
              style: TextStyle(
                fontSize: 12,
                color: style.text.withOpacity(0.75),
                decoration: t.crossed ? TextDecoration.lineThrough : TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _cycleStatus(_TaskItem t) {
    setState(() {
      if (t.status == TaskStatus.newTask) {
        t.status = TaskStatus.inProgress;
      } else if (t.status == TaskStatus.inProgress) {
        t.status = TaskStatus.done;
      } else {
        t.status = TaskStatus.newTask;
      }
    });
  }

  // ---------- Filtering ----------

  List<_TaskItem> _filteredTasks() {
    final list = _tasks.where((t) {
      if (_archiveView) return t.archived;
      if (t.archived) return false; // архив скрываем, если не в архиве
      if (_selectedFolderId == null) return true; // все
      return t.folderId == _selectedFolderId;
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
        _TaskItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: text,
          createdAt: DateTime.now(),
          folderId: _archiveView ? null : _selectedFolderId,
          archived: false,
        ),
      );
      _input.clear();
    });
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
        _TaskItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: '📎 $type',
          createdAt: DateTime.now(),
          folderId: _archiveView ? null : _selectedFolderId,
        ),
      );
    });
  }

  void _openTaskMenu(_TaskItem t) {
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
            ListTile(
              leading: Icon(t.crossed ? Icons.format_strikethrough : Icons.format_strikethrough),
              title: Text(t.crossed ? 'Снять зачёркивание' : 'Зачеркнуть'),
              onTap: () {
                Navigator.pop(context);
                setState(() => t.crossed = !t.crossed);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(t.archived ? 'Убрать из архива' : 'В архив'),
              onTap: () {
                Navigator.pop(context);
                setState(() => t.archived = !t.archived);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _tasks.removeWhere((x) => x.id == t.id));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveTaskFullScreen(_TaskItem t) async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => _MoveTaskPage(
          folders: _folders,
          currentFolderId: t.folderId,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      t.folderId = result.isEmpty ? null : result;
      t.archived = false; // если переносим — выводим из архива
      _archiveView = false;
    });
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
      _folders.add(_FolderItem(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name));
    });
  }

  void _editFolder(_FolderItem f) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                    if (t.folderId == f.id) t.folderId = null;
                  }
                  if (_selectedFolderId == f.id) _selectedFolderId = null;
                });
              },
            ),
          ],
        ),
      ),
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

  _TaskStyle _taskStyle(_TaskItem t) {
    // “как на хорошем скрине” — светлые пастельные
    switch (t.status) {
      case TaskStatus.done:
        return _TaskStyle(
          bg: const Color(0xFFD6F5E3),
          border: const Color(0xFF9ED7B8),
          text: const Color(0xFF1D6B3C),
        );
      case TaskStatus.inProgress:
        return _TaskStyle(
          bg: const Color(0xFFFFF1CC),
          border: const Color(0xFFE6C96A),
          text: const Color(0xFF7A5A00),
        );
      case TaskStatus.newTask:
      default:
        return _TaskStyle(
          bg: const Color(0xFFFFD6DC),
          border: const Color(0xFFE59AA8),
          text: const Color(0xFF7E2433),
        );
    }
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

class _MoveTaskPageState extends State<_MoveTaskPage> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentFolderId; // может быть null
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
