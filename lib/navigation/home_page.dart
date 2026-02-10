import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/inbox/inbox_page.dart';
import '../features/contact/contact_page.dart';
import '../features/profile/profile_page.dart';
import '../features/structure/structure_page.dart';
import '../features/tasks/tasks_page.dart';
import '../shared/label_catalog.dart';
import '../shared/label_models.dart';
import '../shared/contact_store.dart';
import '../shared/conversation_store.dart';
import '../shared/incoming_gateway.dart';
import '../shared/message_source.dart';
import '../shared/phone_utils.dart';
import '../shared/source_settings_store.dart';

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

  // Дебаунс для поиска: уменьшаем количество пересборок и фильтраций в debug,
  // чтобы избежать "Skipped frames" / ANR на слабых эмуляторах.
  Timer? _searchDebounce;
  String _searchQueryRaw = '';
  String _searchQuery = '';
  bool _searchActive = false;

  List<LabelItem> _allLabels = LabelCatalog.instance.labels;

  final Set<String> _selectedLabelNames = {};

  // Ключ для доступа к состоянию TasksPage (чтобы кнопка ➕ жила в общем AppBar)
  final GlobalKey _tasksPageKey = GlobalKey();
  final _conversations = ConversationStore.instance;

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
    _searchDebounce?.cancel();
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
        onLabelsAppliedExternally: (updated) {
          LabelCatalog.instance.replaceAll(updated);
          setState(() => _allLabels = updated);
        },
      ),
      const StructurePage(),
      const ProfilePage(),
      TasksPage(key: _tasksPageKey),
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
          BottomNavigationBarItem(icon: Icon(Icons.account_tree), label: 'Контакты'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Настройки'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Задачи'),
        ],
      ),
      floatingActionButton: _buildFab(),
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

  Widget? _buildFab() {
    if (_currentIndex == 1) {
      // Контакты: быстрый плюс
      return FloatingActionButton(
        onPressed: _openQuickAddContact,
        tooltip: 'Добавить контакт',
        child: const Icon(Icons.add),
      );
    }
    if (_currentIndex == 0) {
      // Входящие: симулятор отключён (только реальные источники).
      return null;
    }

    return null;
  }

  Future<void> _openQuickAddContact() async {
    FocusScope.of(context).unfocus();
    final clip = await Clipboard.getData('text/plain');
    final clipText = (clip?.text ?? '').trim();
    final suggested = PhoneUtils.normalizeRuPhone(clipText);

    String raw = '';
    final phoneCtrl = TextEditingController();
    bool addWhatsApp = true;
    bool addTelegram = true;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final normalized = PhoneUtils.normalizeRuPhone(raw);
            final canSave = normalized.isNotEmpty;
            final canPaste = suggested.isNotEmpty && normalized.isEmpty;

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Новый контакт', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Телефон',
                        hintText: '+7 901 111-11-11',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setLocal(() => raw = v),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: addWhatsApp,
                      onChanged: (v) => setLocal(() => addWhatsApp = v),
                      title: const Text('Добавить WhatsApp'),
                    ),
                    SwitchListTile(
                      value: addTelegram,
                      onChanged: (v) => setLocal(() => addTelegram = v),
                      title: const Text('Добавить Telegram'),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Проверку, что номер реально существует в WhatsApp/Telegram,\nсделаем позже при подключении источников.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: canPaste
                          ? () => setLocal(() { raw = suggested; phoneCtrl.text = suggested; })
                          : (!canSave
                              ? null
                              : () {
                                  final c = ContactStore.instance.getOrCreateByPhone(
                                    phoneInput: normalized,
                                    addWhatsApp: addWhatsApp,
                                    addTelegram: addTelegram,
                                  );
                                  if (addWhatsApp) {
                                    _conversations.ensureConversation(
                                      source: MessageSource.whatsapp,
                                      handle: normalized,
                                      contactId: c.id,
                                      lastMessage: 'Контакт создан',
                                    );
                                  }
                                  if (addTelegram) {
                                    _conversations.ensureConversation(
                                      source: MessageSource.telegram,
                                      handle: normalized,
                                      contactId: c.id,
                                      lastMessage: 'Контакт создан',
                                    );
                                  }

                                  Navigator.of(ctx).pop();

                                  // Открываем карточку контакта
                                  if (!mounted) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => ContactPage(contactId: c.id)),
                                  );
                                }),
                      icon: Icon(canPaste ? Icons.content_paste : Icons.person_add),
                      label: Text(
                        canPaste ? 'Вставить $suggested' : (canSave ? 'Сохранить $normalized' : 'Введите телефон'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openMockIncomingDialog() async {
    FocusScope.of(context).unfocus();
    MessageSource src = MessageSource.whatsapp;
    String handle = '';
    String msg = '';
    String displayName = '';

    final clip = await Clipboard.getData('text/plain');
    final clipText = (clip?.text ?? '').trim();
    final suggestedPhone = PhoneUtils.normalizeRuPhone(clipText);
    if (suggestedPhone.isNotEmpty) {
      handle = suggestedPhone;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final normHandle = PhoneUtils.normalizeForHandle(handle);
            final canSend = normHandle.trim().isNotEmpty && msg.trim().isNotEmpty;

            final enabledSources = SourceSettingsStore.instance.enabledList();
            final sourcesForUi = enabledSources.isNotEmpty
                ? enabledSources
                : [MessageSource.whatsapp, MessageSource.telegram, MessageSource.sms, MessageSource.instagram];

            // Важно: все "входящие" создаём через ConversationStore.addIncomingMessage,
            // чтобы гарантировать проход через getOrCreateForIncoming.
            void addIncoming({
              required MessageSource source,
              required String inHandle,
              required String inMsg,
              required String inName,
            }) {
              final h = PhoneUtils.normalizeForHandle(inHandle);
              _conversations.addIncomingMessage(
                source: source,
                handle: h,
                messageText: inMsg,
                displayName: inName.trim().isEmpty ? h : inName.trim(),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Смоделировать входящее', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),

                    // Быстрые пресеты источников
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: sourcesForUi
                          .map(
                            (s) => _SourceChip(
                              label: s.label,
                              source: s,
                              selected: src == s,
                              onTap: () => setLocal(() => src = s),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 12),

                    // Быстрые сценарии для тестирования склейки/ярлыков/привязки.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            final r = Random();
                            String randomPhone() {
                              final p2 = 900 + r.nextInt(100);
                              final rest = 1000000 + r.nextInt(9000000);
                              return '+7$p2$rest';
                            }

                            const names = [
                              'Иван Петров',
                              'Мария Иванова',
                              'Сергей Смирнов',
                              'Анна Кузнецова',
                              'Алексей Орлов',
                              'Ольга Соколова',
                              'Дмитрий Волков',
                            ];
                            const messages = [
                              'Здравствуйте! Сколько стоит доставка?',
                              'Можно уточнить по заказу?',
                              'Оплатил, проверьте пожалуйста.',
                              'Когда будет готово?',
                              'Есть в наличии?',
                              'Можно отправить сегодня?',
                            ];

                            // Добавим пачку входящих (часть с одинаковым номером, чтобы проверить склейку)
                            final base = suggestedPhone.isNotEmpty ? suggestedPhone : randomPhone();
                            for (int i = 0; i < 10; i++) {
                              final same = i < 3; // 3 сообщения с одним номером
                              final h = same ? base : randomPhone();
                              final name = names[r.nextInt(names.length)];
                              final text = messages[r.nextInt(messages.length)];

                              // Чуть разносим источники
                              final sList = sourcesForUi;
                              final s = sList[i % sList.length];

                              addIncoming(source: s, inHandle: h, inMsg: text, inName: name);
                            }
                            Navigator.of(ctx).pop();
                          },
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Добавить 10 входящих'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            final h = PhoneUtils.normalizeRuPhone(handle);
                            if (h.isEmpty) {
                              // если в поле не телефон — просто оставим как есть
                              return;
                            }
                            // Перекидываем на другой источник (в цикле)
                            final next = switch (src) {
                              MessageSource.whatsapp => MessageSource.telegram,
                              MessageSource.telegram => MessageSource.sms,
                              MessageSource.sms => MessageSource.whatsapp,
                              _ => MessageSource.whatsapp,
                            };
                            const msgs = [
                              'Пишу ещё раз, чтобы уточнить.',
                              'Скиньте реквизиты пожалуйста.',
                              'Ок, спасибо!',
                              'Принято 👍',
                            ];
                            final r = Random();
                            addIncoming(source: next, inHandle: h, inMsg: msgs[r.nextInt(msgs.length)], inName: displayName);
                            Navigator.of(ctx).pop();
                          },
                          icon: const Icon(Icons.merge_type),
                          label: const Text('Тот же номер, другой канал'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'Handle/телефон',
                        suffixIcon: suggestedPhone.isNotEmpty
                            ? IconButton(
                                tooltip: 'Вставить из буфера',
                                icon: const Icon(Icons.content_paste),
                                onPressed: () => setLocal(() => handle = suggestedPhone),
                              )
                            : null,
                      ),
                      controller: TextEditingController(text: handle),
                      onChanged: (v) => setLocal(() => handle = v),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Имя (опционально)'),
                      controller: TextEditingController(text: displayName),
                      onChanged: (v) => setLocal(() => displayName = v),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Сообщение'),
                      controller: TextEditingController(text: msg),
                      onChanged: (v) => setLocal(() => msg = v),
                    ),
                    const SizedBox(height: 12),

                    // Один тап: сгенерировать + добавить входящее (чтобы быстро плодить тесты)
                    OutlinedButton.icon(
                      onPressed: () {
                        final r = Random();
                        String randomPhone() {
                          // +79XXXXXXXXX
                          final p2 = 900 + r.nextInt(100);
                          final rest = 1000000 + r.nextInt(9000000);
                          return '+7$p2$rest';
                        }

                        const names = [
                          'Иван Петров',
                          'Мария Иванова',
                          'Сергей Смирнов',
                          'Анна Кузнецова',
                          'Алексей Орлов',
                          'Ольга Соколова',
                          'Дмитрий Волков',
                        ];
                        const messages = [
                          'Здравствуйте! Сколько стоит доставка?',
                          'Можно уточнить по заказу?',
                          'Оплатил, проверьте пожалуйста.',
                          'Когда будет готово?',
                          'Есть в наличии?',
                          'Можно отправить сегодня?',
                        ];

                        final genHandle = suggestedPhone.isNotEmpty ? suggestedPhone : randomPhone();
                        final genName = names[r.nextInt(names.length)];
                        final genMsg = messages[r.nextInt(messages.length)];

                        setLocal(() {
                          handle = genHandle;
                          displayName = genName;
                          msg = genMsg;
                        });

                        final normHandle2 = PhoneUtils.normalizeForHandle(genHandle);
                        _conversations.addIncomingMessage(
                          source: src,
                          handle: normHandle2,
                          messageText: genMsg,
                          displayName: genName,
                        );
                      },
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Быстро: сгенерировать и добавить'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: !canSend
                          ? null
                          : () {
                              _conversations.addIncomingMessage(
                                source: src,
                                handle: normHandle,
                                messageText: msg.trim(),
                                displayName: displayName.trim().isEmpty ? normHandle : displayName.trim(),
                              );
                              Navigator.of(ctx).pop();
                            },
                      icon: const Icon(Icons.send),
                      label: const Text('Добавить входящее'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  PreferredSizeWidget? _buildAppBarForTab(String? selectedLabelName) {
    // На других вкладках — простой заголовок (и НЕ даём вторую "Задачи" внутри TasksPage)
    if (_currentIndex != 0) {
      return AppBar(
        title: Text(_titleForTab(_currentIndex)),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: _currentIndex == 3
            ? [
                IconButton(
                  tooltip: 'Добавить папку',
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final st = _tasksPageKey.currentState;
                    if (st == null) return;
                    // Дёргаем метод на состоянии TasksPage (без жёсткой зависимости от типа)
                    try {
                      // ignore: avoid_dynamic_calls
                      (st as dynamic).openCreateFolderDialog();
                    } catch (_) {
                      // no-op
                    }
                  },
                ),
              ]
            : null,
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
            onChanged: (v) {
              // Не даём поиску случайно активироваться при переключении источника
              FocusScope.of(context).unfocus();
              setState(() => _selectedSource = v);
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 40,
              child: Focus(
                // Важно: поиск активируется только по тапу по полю.
                // Тут ловим Backspace/Delete, чтобы можно было снять выбранный ярлык как "удаление символа".
                onKeyEvent: (node, event) {
                  final isDown = event is KeyDownEvent;
                  final isBackspace = event.logicalKey == LogicalKeyboardKey.backspace;
                  final isDelete = event.logicalKey == LogicalKeyboardKey.delete;
                  if (isDown && (isBackspace || isDelete)) {
                    if (_searchController.text.isEmpty && _selectedLabelNames.isNotEmpty) {
                      setState(() => _selectedLabelNames.clear());
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  autofocus: false,
                  onChanged: (v) {
                    _searchQueryRaw = v;
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 160), () {
                      if (!mounted) return;
                      final next = _searchQueryRaw.trim();
                      if (next == _searchQuery) return;
                      setState(() => _searchQuery = next);
                    });
                  },
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
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchQueryRaw = '';
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
        return 'Контакты';
      case 2:
        return 'Настройки';
      case 3:
        return 'Задачи';
      default:
        return 'Messenger CRM';
    }
  }

  void _openLabelsFullScreenFilter() async {
    // Не активируем поиск при открытии/закрытии экрана ярлыков
    FocusScope.of(context).unfocus();
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

    // Важно: после выбора ярлыка НЕ должны автоматически активироваться поиск/клавиатура.
    // Иногда фокус может "вернуться" в TextField после закрытия роутов — жёстко сбрасываем.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
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
    // Ярлыки теперь жёстко связаны с контактами (и, соответственно, с диалогами).
    // Для счётчика берём количество контактов с этим ярлыком.
    final contacts = ContactStore.instance.all;
    int countFor(String labelName) => contacts.where((c) => c.labels.contains(labelName)).length;

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
            title: Text('Все (${contacts.length})'),
            onTap: () {
              // На всякий: не даём фокусу "прыгнуть" в поле поиска при возврате.
              FocusScope.of(context).unfocus();
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(
                context,
                _LabelsFilterResult(onlyLabelName: null, updatedLabels: _labels),
              );
            },
          ),
          const Divider(height: 1),
          ..._labels.map((label) {
            return InkWell(
              onTap: () {
                // На всякий: не даём фокусу "прыгнуть" в поле поиска при возврате.
                FocusScope.of(context).unfocus();
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(
                  context,
                  _LabelsFilterResult(onlyLabelName: label.name, updatedLabels: _labels),
                );
              },
              onLongPress: () => _editLabel(label),
              child: ListTile(
                leading: _ColorDot(color: label.color),
                title: Text('${label.name} (${countFor(label.name)})'),
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


class _SourceChip extends StatelessWidget {
  final String label;
  final MessageSource source;
  final bool selected;
  final VoidCallback onTap;

  const _SourceChip({
    required this.label,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? source.color.withOpacity(0.15) : Colors.black12.withOpacity(0.06);
    final border = selected ? source.color.withOpacity(0.35) : Colors.black12;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(source.icon, size: 16, color: source.color),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
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
            // Иконки каналов делаем чуть крупнее (примерно +20%), чтобы читались как логотипы.
            Icon(value.icon, size: 19),
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

    // По ТЗ: в строке поиска показываем ТОЛЬКО цветной кружок (без текста ярлыка).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 10),
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        InkWell(
          onTap: onClearLabel,
          child: const Icon(Icons.close, size: 16, color: Colors.black54),
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}
