import 'package:flutter/material.dart';
import '../chat/chat_page.dart';
import '../../navigation/home_page.dart'; // LabelItem
import '../../shared/message_source.dart';

class InboxPage extends StatefulWidget {
  final MessageSource selectedSource; // all = все
  final Set<String> selectedLabelNames; // пусто = Все
  final List<LabelItem> allLabels;
  final String searchQuery;

  final VoidCallback onOpenLabelsFilter;

  /// если когда-то будем менять сами ярлыки (цвет/имя) изнутри — отдаём наверх
  final ValueChanged<List<LabelItem>> onLabelsAppliedExternally;

  const InboxPage({
    super.key,
    required this.selectedSource,
    required this.selectedLabelNames,
    required this.allLabels,
    required this.searchQuery,
    required this.onOpenLabelsFilter,
    required this.onLabelsAppliedExternally,
  });

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  late List<_InboxItem> _items;

  @override
  void initState() {
    super.initState();
    _items = [
      _InboxItem(
        displayName: '+7 911 860-24-88',
        handle: '+7 911 860-24-88',
        source: MessageSource.telegram,
        lastMessage: 'Вот тут есть 2 видео как им пользоваться',
        time: '18:51',
        labels: {'Новый заказ'},
      ),
      _InboxItem(
        displayName: 'Светлана',
        handle: '+7 953 324-94-35',
        source: MessageSource.whatsapp,
        lastMessage: 'Да, конечно. Но только пуансонов у нас сейчас мало…',
        time: '18:50',
        labels: {'Ожидание платежа'},
      ),
      _InboxItem(
        displayName: 'Elena',
        handle: '@elena_shop',
        source: MessageSource.whatsapp,
        lastMessage: 'И мы вас ❤️',
        time: '18:36',
        labels: {'Оплачен'},
      ),
      _InboxItem(
        displayName: 'Анастасия',
        handle: '@anastasia',
        source: MessageSource.instagram,
        lastMessage: '😋😋😋',
        time: '18:19',
        labels: {'Не оформлен'},
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.searchQuery.trim().toLowerCase();

    final filtered = _items.where((item) {
      final sourceOk = widget.selectedSource.isAll ? true : item.source == widget.selectedSource;

      // сначала фильтр по ярлыку, потом поиск (как ты просил)
      final labelsOk = widget.selectedLabelNames.isEmpty
          ? true
          : item.labels.any((l) => widget.selectedLabelNames.contains(l));

      final searchOk = q.isEmpty
          ? true
          : item.displayName.toLowerCase().contains(q) ||
              item.handle.toLowerCase().contains(q) ||
              item.lastMessage.toLowerCase().contains(q);

      return sourceOk && labelsOk && searchOk;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ничего не найдено', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: widget.onOpenLabelsFilter,
              icon: const Icon(Icons.label_outline),
              label: const Text('Списки'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = filtered[index];

        final labelDots = item.labels.take(4).map((name) {
          final label = widget.allLabels.firstWhere(
            (l) => l.name == name,
            orElse: () => LabelItem(name: name, color: Colors.grey),
          );
          return _LabelDotOnly(color: label.color);
        }).toList();

        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ChatPage(name: item.displayName)),
            );
          },
          onLongPress: () => _openChatContextMenu(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AvatarWithChannelBadge(title: item.displayName, source: item.source),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.displayName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(item.handle,
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Text(item.lastMessage,
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(item.time,
                        style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 6,
                      children: labelDots,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openChatContextMenu(_InboxItem item) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(item.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(item.handle),
              ),
              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Открыть контакт'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Карточка контакта — следующий шаг')),
                  );
                },
              ),

              ListTile(
                leading: const Icon(Icons.label_outline),
                title: const Text('Ярлыки'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openLabelsCheckboxSheet(item);
                },
              ),

              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: const Text('Закрепить'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Закрепление — добавим позже')),
                  );
                },
              ),

              ListTile(
                leading: const Icon(Icons.mark_email_unread_outlined),
                title: const Text('Пометить непрочитанным'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Непрочитано — добавим позже')),
                  );
                },
              ),

              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Заблокировать'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Блокировка — добавим позже')),
                  );
                },
              ),

              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Удалить'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Удаление — добавим позже')),
                  );
                },
              ),

              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _openLabelsCheckboxSheet(_InboxItem item) {
    final temp = Set<String>.from(item.labels);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: StatefulBuilder(
              builder: (ctx2, setLocal) {
                return Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Ярлыки', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: widget.allLabels.length,
                        itemBuilder: (c, i) {
                          final l = widget.allLabels[i];
                          final on = temp.contains(l.name);
                          return CheckboxListTile(
                            value: on,
                            onChanged: (v) {
                              setLocal(() {
                                if (v == true) {
                                  temp.add(l.name);
                                } else {
                                  temp.remove(l.name);
                                }
                              });
                            },
                            title: Row(
                              children: [
                                _Dot(color: l.color),
                                const SizedBox(width: 10),
                                Text(l.name),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            // ✅ ВОТ ТУТ ТЕПЕРЬ СОХРАНЯЕМ
                            setState(() => item.labels = Set<String>.from(temp));
                            Navigator.pop(ctx);
                          },
                          child: const Text('Готово'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _InboxItem {
  final String displayName;
  final String handle;
  final MessageSource source;
  final String lastMessage;
  final String time;
  Set<String> labels; // ВАЖНО: теперь НЕ final, чтобы сохранять

  _InboxItem({
    required this.displayName,
    required this.handle,
    required this.source,
    required this.lastMessage,
    required this.time,
    required this.labels,
  });
}

class _AvatarWithChannelBadge extends StatelessWidget {
  final String title;
  final MessageSource source;

  const _AvatarWithChannelBadge({required this.title, required this.source});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 24,
          child: Text(title.isNotEmpty ? title[0] : '?', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              color: source.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(source.icon, size: 13, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _LabelDotOnly extends StatelessWidget {
  final Color color;
  const _LabelDotOnly({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}
