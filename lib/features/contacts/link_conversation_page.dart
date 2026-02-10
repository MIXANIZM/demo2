import 'package:flutter/material.dart';

import '../../shared/conversation_models.dart';
import '../../shared/contact_models.dart';
import '../../shared/contact_store.dart';
import '../../shared/conversation_store.dart';
import '../../shared/message_source.dart';
import '../../shared/phone_utils.dart';
import '../contact/contact_page.dart';

/// Экран ручной привязки диалога к контакту.
///
/// Нужен на случай:
/// - handle не телефон
/// - ошибочная автосклейка
class LinkConversationPage extends StatefulWidget {
  final String conversationId;

  const LinkConversationPage({super.key, required this.conversationId});

  @override
  State<LinkConversationPage> createState() => _LinkConversationPageState();
}

class _LinkConversationPageState extends State<LinkConversationPage> {
  final _searchCtrl = TextEditingController();
  final _focus = FocusNode();

  Future<void> _linkAndClose(String conversationId, String contactId) async {
    FocusScope.of(context).unfocus();
    // Важно: при привязке мы также добавляем канал в контакт,
    // чтобы в будущем автосвязь по (source+handle) работала стабильно.
    await ConversationStore.instance.linkConversationToContact(conversationId, contactId, alsoUpsertChannel: true);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conv = ConversationStore.instance.tryGet(widget.conversationId);
    if (conv == null) {
      return const Scaffold(
        body: Center(child: Text('Диалог не найден')),
      );
    }

    final contacts = ContactStore.instance.all;
    final q = _searchCtrl.text.trim().toLowerCase();

    // Подсказка по совпадению телефона: если handle выглядит как RU-телефон,
    // покажем контакты, у которых уже есть такой номер в любом канале.
    final convPhone = PhoneUtils.normalizeRuPhone(conv.handle);
    final suggestedByPhone = convPhone.isEmpty
        ? <Contact>[]
        : contacts
            .where((c) => c.channels.any((ch) => PhoneUtils.normalizeRuPhone(ch.handle) == convPhone))
            .toList(growable: false);

    List<Contact> filtered = contacts;
    if (q.isNotEmpty) {
      filtered = contacts.where((c) {
        final title = c.preferredTitle.toLowerCase();
        final company = c.company.trim().toLowerCase();
        final channels = c.channels.map((e) => e.handle.toLowerCase()).join(' ');
        return title.contains(q) || company.contains(q) || channels.contains(q);
      }).toList();
    }

    final current = ContactStore.instance.tryGet(conv.contactId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Привязать к контакту'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: conv.source.color, shape: BoxShape.circle),
                      child: Icon(conv.source.icon, size: 16, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${conv.source.label} • ${conv.handle}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'При привязке этот канал будет добавлен в контакт.',
                  style: TextStyle(color: Colors.black.withOpacity(0.6)),
                ),
                const SizedBox(height: 10),
                if (current != null)
                  Row(
                    children: [
                      const Icon(Icons.link, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Сейчас: ${current.preferredTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ContactPage(contactId: current.id)),
                          );
                        },
                        child: const Text('Открыть'),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchCtrl,
                  focusNode: _focus,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Поиск контактов…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      FocusScope.of(context).unfocus();
                      final c = await ConversationStore.instance.createNewContactAndLink(widget.conversationId);
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => ContactPage(contactId: c.id)),
                      );
                    },
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Создать новый контакт и привязать'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Контактов не найдено'),
                          const SizedBox(height: 10),
                          Text(
                            'Можно создать новый контакт и сразу привязать канал.',
                            style: TextStyle(color: Colors.black.withOpacity(0.6)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: () async {
                              FocusScope.of(context).unfocus();
                              final c = await ConversationStore.instance.createNewContactAndLink(widget.conversationId);
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(builder: (_) => ContactPage(contactId: c.id)),
                              );
                            },
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Создать и привязать'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      if (q.isEmpty && suggestedByPhone.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_awesome, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Совпадение по телефону: $convPhone',
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...suggestedByPhone.map((c) => _ContactRow(
                              contact: c,
                              conv: conv,
                              onTap: () => _linkAndClose(widget.conversationId, c.id),
                            )),
                        const Divider(height: 1),
                      ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                        child: Text(
                          q.isEmpty ? 'Все контакты' : 'Результаты поиска',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      ...filtered.map(
                        (c) => _ContactRow(
                          contact: c,
                          conv: conv,
                          onTap: () => _linkAndClose(widget.conversationId, c.id),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final Contact contact;
  final Conversation conv;
  final VoidCallback onTap;

  const _ContactRow({required this.contact, required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[];
    if (contact.company.trim().isNotEmpty) subtitleParts.add(contact.company.trim());
    if (contact.channels.isNotEmpty) subtitleParts.add(contact.channels.map((e) => e.handle).join(' • '));
    final subtitle = subtitleParts.join(' — ');

    final isCurrent = contact.id == conv.contactId;
    final alreadyHasThisChannel = contact.channels.any(
      (ch) => ch.source == conv.source && ch.handle.trim().toLowerCase() == conv.handle.trim().toLowerCase(),
    );

    return Column(
      children: [
        ListTile(
          leading: isCurrent
              ? const Icon(Icons.check_circle, color: Colors.green)
              : const Icon(Icons.person_outline),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  contact.preferredTitle,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (alreadyHasThisChannel)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Канал уже есть',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          subtitle: subtitle.isEmpty
              ? null
              : Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: onTap,
        ),
        const Divider(height: 1),
      ],
    );
  }
}
