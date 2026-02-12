import 'package:flutter/material.dart';

import '../chat/chat_page.dart';
import '../../shared/contact_models.dart';
import '../../shared/contact_store.dart';
import '../../shared/conversation_store.dart';
import '../../shared/bridge_chat_launcher.dart';
import '../../shared/db_service.dart';
import '../../shared/phone_utils.dart';
import '../../shared/label_catalog.dart';
import '../../shared/label_models.dart';
import '../../shared/message_source.dart';
import '../../matrix/matrix_service.dart';

class ContactPage extends StatefulWidget {
  final String contactId;

  const ContactPage({super.key, required this.contactId});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  Contact? get _contact => ContactStore.instance.tryGet(widget.contactId);

  @override
  Widget build(BuildContext context) {
    final contact = _contact;

    if (contact == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Контакт')),
        body: const Center(child: Text('Контакт не найден')),
      );
    }

    final primary = _pickPrimaryChannel(contact);
    final channelsSorted = List<ContactChannel>.from(contact.channels)
      ..sort((a, b) {
        final ap = a.isPrimary ? 0 : 1;
        final bp = b.isPrimary ? 0 : 1;
        if (ap != bp) return ap - bp;
        final s = a.source.name.compareTo(b.source.name);
        if (s != 0) return s;
        return a.handle.compareTo(b.handle);
      });
    final allLabels = LabelCatalog.instance.labels;

    return Scaffold(
      appBar: AppBar(
        title: Text(contact.preferredTitle),
        actions: [
          IconButton(
            tooltip: 'Редактировать',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await _openEditContactSheet(contact);
              if (!mounted) return;
              setState(() {});
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Ещё',
            onSelected: (v) async {
              if (v == 'delete_contact') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) {
                    return AlertDialog(
                      title: const Text('Удалить контакт?'),
                      content: const Text(
                        'Контакт будет удалён из базы приложения вместе с каналами, заметками, ярлыками и чатами внутри приложения. В Telegram/WhatsApp это ничего не удалит.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Отмена'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Удалить'),
                        ),
                      ],
                    );
                  },
                );
                if (ok == true) {
                  await ContactStore.instance.deleteContact(contact.id);
                  if (!mounted) return;
                  Navigator.of(context).pop();
                }
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'delete_contact',
                child: Text('Удалить контакт'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(contact: contact, primary: primary),
          const SizedBox(height: 16),

          _SectionTitleRow(
            title: 'Каналы',
            actionIcon: Icons.add,
            onAction: () async {
              await _openAddOrEditChannelSheet(contact);
              if (!mounted) return;
              setState(() {});
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: channelsSorted.map((ch) {
              return _ChannelChip(
                channel: ch,
                onTap: () async {
                  // Special case: Telegram by PHONE should open the real bridge portal room, not a "fake" phone-handle chat.
                  if (ch.source == MessageSource.telegram) {
                    final phone = PhoneUtils.normalizeRuPhone(ch.handle);
                    if (phone.isNotEmpty) {
                      await _openTelegramByPhone(contactId: contact.id, phoneE164: phone);
                      return;
                    }
                  }

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        contactId: contact.id,
                        channelSource: ch.source,
                        channelHandle: ch.handle,
                      ),
                    ),
                  );
                },
                onLongPress: () async {
                  await _openChannelActionsSheet(contact, ch);
                  if (!mounted) return;
                  setState(() {});
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 22),
          _SectionTitleRow(
            title: 'Ярлыки',
            actionIcon: Icons.edit_outlined,
            onAction: () => _openLabelsEditor(contact, allLabels),
          ),
          const SizedBox(height: 10),
          _LabelsWrap(
            labels: contact.labels,
            allLabels: allLabels,
          ),

          const SizedBox(height: 22),
          _SectionTitleRow(
            title: 'Заметки',
            actionIcon: Icons.note_add_outlined,
            onAction: () => _openAddNoteSheet(contact),
          ),
          const SizedBox(height: 10),
          if (contact.notes.isEmpty)
            const Text('Пока нет заметок', style: TextStyle(color: Colors.black54))
          else
            ...contact.notes.map(
              (n) => _NoteCard(
                note: n,
                onDelete: () async {
                  await ContactStore.instance.deleteNote(contact.id, n.id);
                  setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }


  ContactChannel? _pickPrimaryChannel(Contact contact) {
    for (final ch in contact.channels) {
      if (ch.isPrimary) return ch;
    }
    return contact.channels.isNotEmpty ? contact.channels.first : null;
  }

  Future<void> _openTelegramByPhone({required String contactId, required String phoneE164}) async {
    // Show progress while we ask the bridge to create a portal room.
    if (!mounted) return;
    final progress = ValueNotifier<String>('Подключаюсь к Matrix…');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(ctx).dialogBackgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ValueListenableBuilder<String>(
            valueListenable: progress,
            builder: (_, v, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(v, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );

    String? roomId;
    try {
      final ok = await MatrixService.instance.ensureOnline(timeout: const Duration(seconds: 6), requireFreshSync: true);
      if (!ok) {
        roomId = null;
      } else {
        roomId = await BridgeChatLauncher.openTelegramByPhone(
          phoneE164,
          displayName: ContactStore.instance.tryGet(contactId)?.preferredTitle,
          onProgress: (stage) => progress.value = stage,
        );
      }
    } catch (_) {
      roomId = null;
    }

    progress.dispose();

    if (mounted) Navigator.of(context).pop();

    if (roomId == null || roomId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось создать Telegram-чат через мост. Если только что был офлайн — переподключи Matrix в настройках и попробуй снова.')),
      );
      return;
    }

    // Promote to non-null outside of closures.
    final rid = roomId;

    // Create/refresh a conversation entry pointing to the REAL Matrix room id.
    ConversationStore.instance.upsertPreview(
      source: MessageSource.telegram,
      handle: rid,
      contactId: contactId,
      lastMessage: 'Telegram: $phoneE164',
      updatedAt: DateTime.now(),
    );
    await DbService.instance.linkRoomToContact(roomId: rid, contactId: contactId);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          contactId: contactId,
          channelSource: MessageSource.telegram,
          channelHandle: rid,
        ),
      ),
    );
  }

  Future<void> _openEditContactSheet(Contact contact) async {
    final firstCtrl = TextEditingController(text: contact.firstName);
    final lastCtrl = TextEditingController(text: contact.lastName);
    final companyCtrl = TextEditingController(text: contact.company);
    final displayCtrl = TextEditingController(text: contact.displayName);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(left: 16, right: 16, top: 14, bottom: bottom + 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              const Text('Редактировать контакт', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(
                controller: firstCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Имя',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: lastCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Фамилия',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: companyCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Компания',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: displayCtrl,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Отображаемое имя (если имя/фамилия пустые)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final first = firstCtrl.text;
                        final last = lastCtrl.text;
                        final company = companyCtrl.text;
                        String display = displayCtrl.text.trim();
                        final full = [first.trim(), last.trim()].where((e) => e.isNotEmpty).join(' ');
                        if (full.isNotEmpty) {
                          // Чтобы везде (в том числе во входящих) сразу показывалось имя.
                          display = full;
                        }
                        await ContactStore.instance.updateContact(
                          contact.id,
                          firstName: first,
                          lastName: last,
                          company: company,
                          displayName: display.isEmpty ? contact.displayName : display,
                        );
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Сохранить'),
                    ),
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

  Future<void> _openAddOrEditChannelSheet(Contact contact, {ContactChannel? existing}) async {
    MessageSource selected = existing?.source ?? MessageSource.whatsapp;
    bool makePrimary = existing?.isPrimary ?? true;
    final handleCtrl = TextEditingController(text: existing?.handle ?? '');
    final oldSource = existing?.source;
    final oldHandle = existing?.handle;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 14, bottom: bottom + 14),
          child: StatefulBuilder(
            builder: (ctx2, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(existing == null ? 'Добавить канал' : 'Редактировать канал', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<MessageSource>(
                    value: selected,
                    decoration: InputDecoration(
                      labelText: 'Источник',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      isDense: true,
                    ),
                    items: MessageSource.values
                        .where((s) => !s.isAll)
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(s.label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setModal(() => selected = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: handleCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Телефон / @username',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: makePrimary,
                    onChanged: (v) => setModal(() => makePrimary = v),
                    title: const Text('Сделать основным'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            // Если редактируем и сменился источник — удалим старый канал,
                            // чтобы не было дубликатов (канал у нас уникален по source).
                            if (oldSource != null && oldSource != selected) {
                              await ContactStore.instance.removeChannel(contact.id, oldSource);
                            }
                            await ContactStore.instance.upsertChannel(
                              contact.id,
                              source: selected,
                              handle: handleCtrl.text,
                              makePrimary: makePrimary,
                            );
                            Navigator.of(ctx).pop();
                          },
                          child: Text(existing == null ? 'Добавить' : 'Сохранить'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openChannelActionsSheet(Contact contact, ContactChannel channel) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Text(channel.source.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(channel.handle, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
                            ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Редактировать канал'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _openAddOrEditChannelSheet(contact, existing: channel);
                },
              ),
ListTile(
                enabled: !channel.isPrimary,
                leading: const Icon(Icons.star_outline),
                title: const Text('Сделать основным'),
                onTap: () {
                  ContactStore.instance.setPrimaryChannelByHandle(contact.id, channel.source, channel.handle);
                  Navigator.of(ctx).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Выбрать основной…'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _openPrimaryPicker(contact, current: channel);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Удалить канал'),
                onTap: () async {
                  await ContactStore.instance.removeChannel(contact.id, channel.source);
                  Navigator.of(ctx).pop();
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPrimaryPicker(Contact contact, {ContactChannel? current}) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final items = List<ContactChannel>.from(contact.channels);
        items.sort((a, b) {
          final ap = a.isPrimary ? 0 : 1;
          final bp = b.isPrimary ? 0 : 1;
          if (ap != bp) return ap - bp;
          final s = a.source.name.compareTo(b.source.name);
          if (s != 0) return s;
          return a.handle.compareTo(b.handle);
        });

        final selected = current ?? _pickPrimaryChannel(contact);

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const Text('Основной канал', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...items.map((ch) {
                final value = '${ch.source.name}::${ch.handle}';
                final group = selected == null ? '' : '${selected.source.name}::${selected.handle}';
                return RadioListTile<String>(
                  value: value,
                  groupValue: group,
                  onChanged: (v) {
                    ContactStore.instance.setPrimaryChannelByHandle(contact.id, ch.source, ch.handle);
                    Navigator.of(ctx).pop();
                  },
                  title: Text(ch.source.label),
                  subtitle: Text(ch.handle, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              }),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }


  Future<void> _openAddNoteSheet(Contact contact, {String? seedText}) async {
    final controller = TextEditingController(text: seedText ?? '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 14, bottom: bottom + 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Новая заметка', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 5,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Напиши заметку…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final text = controller.text.trim();
                        if (text.isEmpty) {
                          Navigator.of(ctx).pop();
                          return;
                        }
                        await ContactStore.instance.addNote(contact.id, text);
                        Navigator.of(ctx).pop();
                        setState(() {});
                      },
                      child: const Text('Сохранить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openLabelsEditor(Contact contact, List<LabelItem> allLabels) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const Text('Ярлыки контакта', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: allLabels.length,
                  itemBuilder: (_, i) {
                    final l = allLabels[i];
                    final selected = contact.labels.contains(l.name);
                    return ListTile(
                      onTap: () async {
                        await ContactStore.instance.toggleLabel(contact.id, l.name);
                        setState(() {});
                        // Чтобы список реагировал без закрытия.
                        (ctx as Element).markNeedsBuild();
                      },
                      leading: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(color: l.color, shape: BoxShape.circle),
                      ),
                      title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        color: selected ? Colors.green : Colors.black26,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Готово'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final Contact contact;
  final ContactChannel? primary;

  const _Header({required this.contact, required this.primary});

  @override
  Widget build(BuildContext context) {
    final title = contact.preferredTitle;
    final initials = title.isNotEmpty ? title[0] : '?';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              if (primary != null)
                Row(
                  children: [
                    Icon(primary!.source.icon, size: 18, color: primary!.source.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        primary!.handle,
                        style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _MetaPill(text: 'ID: ${contact.id}'),
                  const SizedBox(width: 8),
                  _MetaPill(text: '${contact.channels.length} канал(ов)'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800));
  }
}

class _SectionTitleRow extends StatelessWidget {
  final String title;
  final IconData actionIcon;
  final VoidCallback onAction;

  const _SectionTitleRow({
    required this.title,
    required this.actionIcon,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SectionTitle(title)),
        IconButton(
          onPressed: onAction,
          icon: Icon(actionIcon),
          splashRadius: 22,
          tooltip: title,
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String text;
  const _MetaPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54),
      ),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  final ContactChannel channel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ChannelChip({
    required this.channel,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final src = channel.source;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: channel.isPrimary ? Colors.black : Colors.black.withOpacity(0.12),
            width: channel.isPrimary ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: src.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Icon(src.icon, size: 18, color: src.color),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                channel.handle,
                style: const TextStyle(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelsWrap extends StatelessWidget {
  final Set<String> labels;
  final List<LabelItem> allLabels;

  const _LabelsWrap({required this.labels, required this.allLabels});

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) {
      return const Text('Пока нет ярлыков', style: TextStyle(color: Colors.black54));
    }

    LabelItem? findMeta(String name) {
      for (final l in allLabels) {
        if (l.name == name) return l;
      }
      return null;
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: labels.map((name) {
        final meta = findMeta(name);
        return Chip(
          visualDensity: VisualDensity.compact,
          label: Text(name),
          avatar: meta == null
              ? null
              : Container(
                  // Размер кружка ярлыка как в диалогах
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle),
                ),
        );
      }).toList(),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final ContactNote note;
  final VoidCallback onDelete;

  const _NoteCard({required this.note, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(note.createdAt),
                  style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(note.text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Удалить заметку?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onDelete();
              },
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} • ${two(dt.hour)}:${two(dt.minute)}';
  }
}
