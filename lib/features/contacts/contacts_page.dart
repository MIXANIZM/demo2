import 'package:flutter/material.dart';

import '../../shared/contact_models.dart';
import '../../shared/contact_store.dart';
import '../../shared/conversation_store.dart';
import '../../shared/label_catalog.dart';
import '../../shared/label_models.dart';
import '../../shared/message_source.dart';
import '../../shared/phone_utils.dart';
import '../contact/contact_page.dart';

/// Список контактов с фильтром по ярлыку.
///
/// Нужен именно для ответа на вопрос:
/// «Где посмотреть всех контактов с ярлыком Оплачен?»
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final _searchCtrl = TextEditingController();
  final _focus = FocusNode();
  String? _selectedLabel; // null = все

  List<Contact> get _allContacts => ContactStore.instance.all;
  List<LabelItem> get _allLabels => LabelCatalog.instance.labels;
  final _conversations = ConversationStore.instance;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = _allContacts.where((c) {
      final labelOk = _selectedLabel == null ? true : c.labels.contains(_selectedLabel);
      if (!labelOk) return false;
      if (q.isEmpty) return true;

      final title = c.preferredTitle.toLowerCase();
      final company = c.company.trim().toLowerCase();
      final channelText = c.channels.map((ch) => ch.handle.toLowerCase()).join(' ');
      return title.contains(q) || company.contains(q) || channelText.contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _focus,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Поиск контактов…',
                    prefixIcon: _selectedLabel == null
                        ? const Icon(Icons.search)
                        : _LabelDotPrefix(
                            labelName: _selectedLabel!,
                            allLabels: _allLabels,
                            onClear: () {
                              setState(() => _selectedLabel = null);
                            },
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  FocusScope.of(context).unfocus();
                  final picked = await _openLabelPicker(context);
                  if (!mounted) return;
                  setState(() => _selectedLabel = picked);
                },
                icon: const Icon(Icons.label_outline),
                label: const Text('Ярлыки'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? _emptyState(context, q)
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    final subtitleParts = <String>[];
                    if (c.company.trim().isNotEmpty) subtitleParts.add(c.company.trim());
                    if (c.channels.isNotEmpty) subtitleParts.add(c.channels.map((e) => e.handle).join(' • '));
                    final subtitle = subtitleParts.join(' — ');

                    return ListTile(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ContactPage(contactId: c.id)),
                        );
                      },
                      title: Text(c.preferredTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: c.labels.isEmpty
                          ? null
                          : _MiniLabelDots(labels: c.labels, allLabels: _allLabels),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context, String queryLower) {
    final raw = _searchCtrl.text.trim();
    final normalizedPhone = PhoneUtils.normalizeRuPhone(raw);
    final canCreateByPhone = raw.isNotEmpty && normalizedPhone.isNotEmpty;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Нет контактов по фильтру', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 10),
          if (canCreateByPhone) ...[
            FilledButton.icon(
              onPressed: () {
                final c = ContactStore.instance.getOrCreateByPhone(phoneInput: normalizedPhone);
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

                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContactPage(contactId: c.id)));
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
          ],
        ],
      ),
    );
  }

  Future<String?> _openLabelPicker(BuildContext context) async {
    return showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) {
        final contacts = ContactStore.instance.all;
        int countFor(String labelName) => contacts.where((c) => c.labels.contains(labelName)).length;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const Text('Фильтр по ярлыку', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              ListTile(
                onTap: () => Navigator.of(ctx).pop(null),
                leading: const Icon(Icons.all_inclusive),
                title: Text('Все контакты (${contacts.length})'),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _allLabels.length,
                  itemBuilder: (_, i) {
                    final l = _allLabels[i];
                    return ListTile(
                      onTap: () => Navigator.of(ctx).pop(l.name),
                      leading: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(color: l.color, shape: BoxShape.circle),
                      ),
                      title: Text('${l.name} (${countFor(l.name)})', style: const TextStyle(fontWeight: FontWeight.w700)),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}

class _LabelDotPrefix extends StatelessWidget {
  final String labelName;
  final List<LabelItem> allLabels;
  final VoidCallback onClear;

  const _LabelDotPrefix({required this.labelName, required this.allLabels, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final label = allLabels.where((e) => e.name == labelName).cast<LabelItem?>().firstWhere((e) => true, orElse: () => null);
    final color = label?.color ?? Colors.black12;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 12),
        Container(width: 20, height: 20, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        IconButton(
          onPressed: onClear,
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Сбросить ярлык',
        ),
      ],
    );
  }
}

class _MiniLabelDots extends StatelessWidget {
  final Set<String> labels;
  final List<LabelItem> allLabels;

  const _MiniLabelDots({required this.labels, required this.allLabels});

  @override
  Widget build(BuildContext context) {
    final items = allLabels.where((l) => labels.contains(l.name)).toList();
    final show = items.take(3).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: show
          .map(
            (l) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Container(width: 20, height: 20, decoration: BoxDecoration(color: l.color, shape: BoxShape.circle)),
            ),
          )
          .toList(),
    );
  }
}
