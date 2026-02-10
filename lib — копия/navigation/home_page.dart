import 'package:flutter/material.dart';

import '../features/inbox/inbox_page.dart';
import '../features/profile/profile_page.dart';
import '../features/structure/structure_page.dart';
import '../features/tasks/tasks_page.dart';
import '../shared/message_source.dart';

class LabelItem {
  String name;
  Color color;

  LabelItem({required this.name, required this.color});
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  MessageSource _selectedSource = MessageSource.all;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  String _searchQuery = '';
  bool _searchActive = false;

  List<LabelItem> _allLabels = [
    LabelItem(name: 'Не оформлен', color: const Color(0xFF4FC3F7)),
    LabelItem(name: 'Новый заказ', color: const Color(0xFFFFD54F)),
    LabelItem(name: 'Ожидание платежа', color: const Color(0xFFFF8A65)),
    LabelItem(name: 'Оплачен', color: const Color(0xFFBA68C8)),
    LabelItem(name: 'Завершённый заказ', color: const Color(0xFF4DB6AC)),
    LabelItem(name: 'Самовывоз', color: const Color(0xFF90A4AE)),
    LabelItem(name: 'Курьер Яндекс', color: const Color(0xFF7986CB)),
  ];

  final Set<String> _selectedLabelNames = {};

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (!mounted) return;
      setState(() => _searchActive = _searchFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<bool> _handleBack() async {
    // 0) Если активен поиск — закрываем поиск
    if (_searchActive) {
      _onCancelSearch();
      return false;
    }

    // 1) Если не на "Входящие" — возвращаемся туда (НЕ выходим из приложения)
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return false;
    }

    // 2) Уже на "Входящие" и поиск закрыт — можно выходить
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final selectedLabelName =
        _selectedLabelNames.isEmpty ? null : _selectedLabelNames.first;

    final pages = <Widget>[
      InboxPage(
        selectedSource: _selectedSource,
        selectedLabelNames: _selectedLabelNames,
        allLabels: _allLabels,
        searchQuery: _searchQuery,
        onOpenLabelsFilter: _openLabelsFullScreenFilter,
        onLabelsAppliedExternally: (updated) => setState(() => _allLabels = updated),
      ),
      const StructurePage(),
      const ProfilePage(),
      const TasksPage(),
    ];

    final app = Scaffold(
      appBar: _buildAppBarForTab(selectedLabelName),
      body: Column(
        children: [
          if (_currentIndex == 0 && _searchActive) _buildTimeFilterStrip(),
          Expanded(child: SafeArea(child: pages[_currentIndex])),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          FocusScope.of(context).unfocus();
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.inbox), label: 'Входящие'),
          BottomNavigationBarItem(icon: Icon(Icons.account_tree), label: 'Структура'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Настройки'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Задачи'),
        ],
      ),
    );

    // PopScope — чтобы кнопка НАЗАД не закрывала приложение, пока мы не на Входящих
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final allow = await _handleBack();
        if (allow && mounted) {
          Navigator.of(context).maybePop(); // здесь ОС закроет приложение
        }
      },
      child: WillPopScope(
        onWillPop: _handleBack,
        child: app,
      ),
    );
  }

  PreferredSizeWidget? _buildAppBarForTab(String? selectedLabelName) {
    // На других вкладках — простой заголовок (и НЕ даём вторую "Задачи" внутри TasksPage)
    if (_currentIndex != 0) {
      return AppBar(
        title: Text(_titleForTab(_currentIndex)),
        elevation: 0,
        scrolledUnderElevation: 0,
      );
    }

    final selectedLabel = selectedLabelName == null
        ? null
        : _allLabels.where((l) => l.name == selectedLabelName).cast<LabelItem?>().firstOrNull;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 8,
      title: Row(
        children: [
          _SourceChipDropdownCompact(
            value: _selectedSource,
            onChanged: (v) => setState(() => _selectedSource = v),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                  prefixIcon: _SearchPrefix(
                    selectedLabel: selectedLabel,
                    onClearLabel: selectedLabel == null
                        ? null
                        : () => setState(() => _selectedLabelNames.clear()),
                  ),
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
                ),
              ),
            ),
          ),
          if (_searchActive) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: _onCancelSearch,
              child: const Text('Отмена'),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Списки',
              icon: const Icon(Icons.label_outline),
              onPressed: _openLabelsFullScreenFilter,
            ),
          ],
        ],
      ),
    );
  }

  void _onCancelSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
    FocusScope.of(context).unfocus();
  }

  Widget _buildTimeFilterStrip() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(color: Colors.white),
      child: Wrap(
        spacing: 8,
        children: [
          _ChipButton(text: 'Сегодня', onTap: () {}),
          _ChipButton(text: 'Вчера', onTap: () {}),
          _ChipButton(text: '7 дней', onTap: () {}),
          _ChipButton(text: 'Диапазон…', onTap: () {}),
        ],
      ),
    );
  }

  String _titleForTab(int index) {
    switch (index) {
      case 1:
        return 'Структура';
      case 2:
        return 'Настройки';
      case 3:
        return 'Задачи';
      default:
        return 'Messenger CRM';
    }
  }

  void _openLabelsFullScreenFilter() async {
    final selectedName = _selectedLabelNames.isEmpty ? null : _selectedLabelNames.first;

    final result = await Navigator.of(context).push<_LabelsFilterResult>(
      MaterialPageRoute(
        builder: (_) => _LabelsFilterPage(labels: _allLabels, currentSelected: selectedName),
      ),
    );

    if (result == null) return;

    setState(() {
      _allLabels = result.updatedLabels;
      _selectedLabelNames.clear();
      if (result.onlyLabelName != null) _selectedLabelNames.add(result.onlyLabelName!);
    });
  }
}

extension _FirstOrNullExt<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

// ---------- Labels Fullscreen ----------

class _LabelsFilterResult {
  final String? onlyLabelName;
  final List<LabelItem> updatedLabels;
  _LabelsFilterResult({required this.onlyLabelName, required this.updatedLabels});
}

class _LabelsFilterPage extends StatefulWidget {
  final List<LabelItem> labels;
  final String? currentSelected;

  const _LabelsFilterPage({required this.labels, required this.currentSelected});

  @override
  State<_LabelsFilterPage> createState() => _LabelsFilterPageState();
}

class _LabelsFilterPageState extends State<_LabelsFilterPage> {
  late List<LabelItem> _labels;

  @override
  void initState() {
    super.initState();
    _labels = widget.labels.map((e) => LabelItem(name: e.name, color: e.color)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Списки')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.black12,
              child: Icon(Icons.add, color: Colors.black87),
            ),
            title: const Text('Новый список'),
            onTap: _createNewLabel,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text('Ваши списки',
                style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const _ColorDot(color: Colors.black26),
            title: const Text('Все'),
            onTap: () => Navigator.pop(
              context,
              _LabelsFilterResult(onlyLabelName: null, updatedLabels: _labels),
            ),
          ),
          const Divider(height: 1),
          ..._labels.map((label) {
            return InkWell(
              onTap: () => Navigator.pop(
                context,
                _LabelsFilterResult(onlyLabelName: label.name, updatedLabels: _labels),
              ),
              onLongPress: () => _editLabel(label),
              child: ListTile(
                leading: _ColorDot(color: label.color),
                title: Text(label.name),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _createNewLabel() async {
    final created = await _openLabelEditDialog(
      context,
      initialName: 'Новый список',
      initialColor: const Color(0xFF90A4AE),
    );

    if (created == null) return;

    setState(() {
      _labels.insert(0, LabelItem(name: created.name, color: created.color));
    });

    if (!mounted) return;
    Navigator.pop(
      context,
      _LabelsFilterResult(onlyLabelName: created.name, updatedLabels: _labels),
    );
  }

  void _editLabel(LabelItem label) async {
    final edited = await _openLabelEditDialog(
      context,
      initialName: label.name,
      initialColor: label.color,
    );
    if (edited == null) return;

    setState(() {
      label.name = edited.name;
      label.color = edited.color;
    });
  }
}

class _EditedLabel {
  final String name;
  final Color color;
  _EditedLabel({required this.name, required this.color});
}

Future<_EditedLabel?> _openLabelEditDialog(
  BuildContext context, {
  required String initialName,
  required Color initialColor,
}) async {
  final nameCtrl = TextEditingController(text: initialName);
  Color chosen = initialColor;

  final palette = <Color>[
    const Color(0xFF4FC3F7),
    const Color(0xFFFFD54F),
    const Color(0xFFFF8A65),
    const Color(0xFFBA68C8),
    const Color(0xFF4DB6AC),
    const Color(0xFF90A4AE),
    const Color(0xFF7986CB),
    const Color(0xFFE57373),
    const Color(0xFF81C784),
    const Color(0xFFFFB74D),
  ];

  return showDialog<_EditedLabel>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Редактировать список'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Цвет',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.65),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: palette.map((c) {
                    final selected = c.value == chosen.value;
                    return InkWell(
                      onTap: () => setLocal(() => chosen = c),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.black : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx, _EditedLabel(name: name, color: chosen));
                },
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ---------- UI helpers ----------

class _ChipButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _ChipButton({required this.text, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black12),
        ),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// уменьшенная кнопка источника (как ты просил)
class _SourceChipDropdownCompact extends StatelessWidget {
  final MessageSource value;
  final ValueChanged<MessageSource> onChanged;

  const _SourceChipDropdownCompact({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MessageSource>(
      tooltip: 'Источник',
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: MessageSource.all, child: Text('Все')),
        PopupMenuItem(value: MessageSource.telegram, child: Text('Telegram')),
        PopupMenuItem(value: MessageSource.whatsapp, child: Text('WhatsApp')),
        PopupMenuItem(value: MessageSource.sms, child: Text('SMS')),
        PopupMenuItem(value: MessageSource.instagram, child: Text('Instagram')),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(value.icon, size: 16),
            const SizedBox(width: 4),
            Text(value.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

// плашка ярлыка внутри поиска
class _SearchPrefix extends StatelessWidget {
  final LabelItem? selectedLabel;
  final VoidCallback? onClearLabel;

  const _SearchPrefix({required this.selectedLabel, required this.onClearLabel});

  @override
  Widget build(BuildContext context) {
    if (selectedLabel == null) return const Icon(Icons.search);

    final c = selectedLabel!.color;
    final bg = c.withOpacity(0.22);

    return SizedBox(
      width: 150,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.withOpacity(0.55)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    selectedLabel!.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: onClearLabel,
                  child: const Icon(Icons.close, size: 16, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
