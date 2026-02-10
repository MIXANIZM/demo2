import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/stores_providers.dart';
import '../chat/chat_page.dart';
import '../contact/contact_page.dart';
import '../../shared/label_models.dart';
import '../../shared/contact_models.dart';
import '../../shared/contact_store.dart';
import '../../shared/conversation_store.dart';
import '../../shared/conversation_models.dart';
import '../../shared/message_source.dart';
import '../../shared/phone_utils.dart';
import '../contacts/link_conversation_page.dart';

class InboxPage extends ConsumerStatefulWidget {
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
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage> {
  List<_InboxItem> get _items => _buildItemsFromConversations(_conversations.all);
  final _store = ContactStore.instance;
  final _conversations = ConversationStore.instance;

  @override
  void initState() {
    super.initState();
    // Demo seed disabled (real data only).
  }

  List<_InboxItem> _buildItemsFromConversations(List<Conversation> convs) {
    String fmtTime(DateTime dt) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }

    return convs
        .map((c) {
          final contact = _store.tryGet(c.contactId);
          final name = contact?.preferredTitle ?? c.handle;
          final isMatrixAsTg = c.source == MessageSource.telegram && c.handle.startsWith('!');
          String phoneOrUser = '';
          if (isMatrixAsTg && contact != null) {
            // Prefer a Telegram channel handle that looks like a phone/username, not a roomId.
            final ch = contact.channels.where((ch) => ch.source == MessageSource.telegram && !ch.handle.startsWith('!')).toList();
            for (final cc in ch) {
              final h = cc.handle.trim();
              if (h.startsWith('+') || h.startsWith('@') || RegExp(r'^\d{7,}$').hasMatch(h)) {
                phoneOrUser = h;
                break;
              }
            }
          }
          return _InboxItem(
            conversationId: c.id,
            unreadCount: c.unreadCount,
            contactId: c.contactId,
            displayName: name,
            handle: c.handle,
            phoneOrUsername: phoneOrUser,
            source: c.source,
            lastMessage: c.lastMessage,
            time: fmtTime(c.updatedAt),
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // Riverpod: пересобираем Inbox при изменениях диалогов/контактов.
    ref.watch(conversationsVersionProvider);
    ref.watch(contactsVersionProvider);

    final q = widget.searchQuery.trim().toLowerCase();

    Set<String> labelsFor(_InboxItem item) {
      final c = _store.tryGet(item.contactId);
      return c?.labels ?? <String>{};
    }

    final filtered = _items.where((item) {
      final sourceOk = widget.selectedSource.isAll ? true : item.source == widget.selectedSource;

      final itemLabels = labelsFor(item);

      // сначала фильтр по ярлыку, потом поиск (как ты просил)
      final labelsOk = widget.selectedLabelNames.isEmpty
          ? true
          : itemLabels.any((l) => widget.selectedLabelNames.contains(l));

      final searchOk = q.isEmpty
          ? true
          : item.displayName.toLowerCase().contains(q) ||
              item.handle.toLowerCase().contains(q) ||
              item.lastMessage.toLowerCase().contains(q);

      return sourceOk && labelsOk && searchOk;
    }).toList();

    if (filtered.isEmpty) {
      final normalizedPhone = PhoneUtils.normalizeRuPhone(widget.searchQuery);
      final canCreateByPhone = normalizedPhone.isNotEmpty;

      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ничего не найдено', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            if (canCreateByPhone) ...[
              FilledButton.icon(
                onPressed: () {
                  final c = _store.getOrCreateByPhone(phoneInput: normalizedPhone);
                  // Создаём 2 диалога-заглушки (WhatsApp + Telegram),
                  // чтобы потом реальные источники «прилипли» к существующей связи.
                  _conversations.ensureConversation(
                    source: MessageSource.whatsapp,
                    handle: normalizedPhone,
                    contactId: c.id,
                    lastMessage: 'Контакт создан',
                  );
                  _conversations.ensureConversation(
                    source: MessageSource.telegram,
                    handle: normalizedPhone,
                    contactId: c.id,
                    lastMessage: 'Контакт создан',
                  );

                  if (!mounted) return;
                                      Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ContactPage(contactId: c.id)),
                  );
                },
                icon: const Icon(Icons.person_add),
                label: Text('Сохранить контакт $normalizedPhone'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Каналы WhatsApp/Telegram добавляются без реальной проверки.\nПроверку сделаем при подключении источников.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
            ],
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

        final itemLabels = labelsFor(item);
        final isMatrixAsTg = item.source == MessageSource.telegram && item.handle.startsWith('!');

        final labelDots = itemLabels.take(4).map((name) {
          final label = widget.allLabels.firstWhere(
            (l) => l.name == name,
            orElse: () => LabelItem(name: name, color: Colors.grey),
          );
          return _LabelDotOnly(color: label.color);
        }).toList();

        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) {
                  final isMatrixRoom = item.handle.startsWith('!');
                  // For Matrix rooms bridged as Telegram, open the WhatsApp-like Chat UI.
                  // ChatPage internally detects Matrix rooms by handle starting with '!'.
                  return ChatPage(
                    conversationId: item.conversationId,
                    contactId: item.contactId,
                    channelSource: item.source,
                    channelHandle: item.handle,
                  );
                },
              ),
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
                      const SizedBox(height: 2),                      if (isMatrixAsTg) ...[
                        Text(
                          item.phoneOrUsername.trim().isNotEmpty ? item.phoneOrUsername : item.handle,
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ] else
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(item.time,
                            style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
                        if (item.unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.shade700,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              item.unreadCount > 99 ? '99+' : '${item.unreadCount}',
                              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ],
                    ),
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
      isScrollControlled: true,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.9;
        final bottomPad = MediaQuery.of(ctx).padding.bottom + 10 + MediaQuery.of(ctx).viewInsets.bottom;
        return SafeArea(
          top: false,
          bottom: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.only(bottom: bottomPad),
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
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ContactPage(contactId: item.contactId)),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Привязать к контакту…'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LinkConversationPage(conversationId: item.conversationId),
                      ),
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
                    ConversationStore.instance.markAsUnread(item.conversationId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Помечено как непрочитанное')),
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
              ],
            ),
          ),
        );
      },
    );
  }

  void _openLabelsCheckboxSheet(_InboxItem item) {
    final contact = _store.tryGet(item.contactId);
    final temp = Set<String>.from(contact?.labels ?? <String>{});

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
                          onPressed: () async {
                            // ✅ Ярлык жёстко связан: сохраняем в Contact.labels (и в БД).
                            // Если контакт ещё не создан/не загружен — создаём его и привязываем к диалогу.
                            var c = contact;
                            if (c == null) {
                              c = await ConversationStore.instance.createNewContactAndLink(item.conversationId);
                            }
                            await ContactStore.instance.setLabels(c.id, temp);
                            if (mounted) Navigator.pop(ctx);
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
  final String conversationId;
  final String contactId;
  final String displayName;
  final String handle;
  final String phoneOrUsername;
  final MessageSource source;
  final String lastMessage;
  final String time;
  final int unreadCount;

  _InboxItem({
    required this.conversationId,
    required this.contactId,
    required this.displayName,
    required this.handle,
    required this.phoneOrUsername,
    required this.source,
    required this.lastMessage,
    required this.time,
    required this.unreadCount,
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
            // Бейдж канала +20% (было 19)
            width: 23,
            height: 23,
            decoration: BoxDecoration(
              color: source.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(source.icon, size: 16, color: Colors.white),
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
