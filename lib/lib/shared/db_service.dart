import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import 'app_db.dart' as db;
import 'contact_models.dart' as models;
import 'conversation_models.dart';
import 'message_source.dart';

/// Единая точка работы с локальной БД (Drift/SQLite).
///
/// Принцип: никаких Riverpod/Bloc. Просто singleton + fire-and-forget.
class DbService {
  DbService._();

  static final DbService instance = DbService._();

  db.AppDb? _db;

  db.AppDb get database {
    final d = _db;
    if (d == null) {
      throw StateError('DbService not initialized');
    }
    return d;
  }

  Future<void> init() async {
    // Создаем БД лениво.
    _db ??= db.AppDb();

    // Важно: без кодогенерации Drift мы можем создавать новые таблицы через raw SQL.
    // Это даст нам хранение сообщений в отдельной таблице messages (MVP).
    await _ensureMessagesTable();
    await _ensureConversationStateTable();
    await _ensureEmojiUsageTable();
  }

  Future<void> _ensureEmojiUsageTable() async {
    final d = database;
    await d.customStatement('''
      CREATE TABLE IF NOT EXISTS emoji_usage (
        emoji TEXT PRIMARY KEY,
        cnt INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );
    ''');
  }

  /// Увеличить счётчик использования эмодзи (для панели быстрых реакций).
  Future<void> bumpEmojiUsage(String emoji) async {
    final d = database;
    await _ensureEmojiUsageTable();
    final now = DateTime.now().millisecondsSinceEpoch;
    await d.customStatement(
      'INSERT INTO emoji_usage(emoji, cnt, updated_at_ms) VALUES (?, 1, ?) '
      'ON CONFLICT(emoji) DO UPDATE SET cnt = cnt + 1, updated_at_ms = excluded.updated_at_ms',
      [emoji, now],
    );
  }

  /// Топ-N самых частых эмодзи в приложении.
  ///
  /// Если счётчики ещё не накоплены, возвращает пустой список.
  Future<List<String>> loadTopEmojis({int limit = 7}) async {
    final d = database;
    await _ensureEmojiUsageTable();
    final rows = await d.customSelect(
      'SELECT emoji FROM emoji_usage ORDER BY cnt DESC, updated_at_ms DESC LIMIT ?',
      variables: [Variable<int>(limit)],
    ).get();
    return rows.map((r) => r.read<String>('emoji')).toList(growable: false);
  }

  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _ensureConversationStateTable() async {
    final d = database;
    await d.customStatement('''
      CREATE TABLE IF NOT EXISTS conversation_state (
        conversation_id TEXT PRIMARY KEY,
        unread_count INTEGER NOT NULL,
        last_read_ms INTEGER NOT NULL
      );
    ''');
  }


  Future<void> _ensureMessagesTable() async {
    final d = database;

    await d.customStatement('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        contact_id TEXT NOT NULL,
        is_outgoing INTEGER NOT NULL,
        text TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        my_reaction TEXT,
        edited_at_ms INTEGER
      );
    ''');

    await d.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_conv_time ON messages(conversation_id, created_at_ms);',
    );

    // Add reaction column if this DB was created before reactions existed.
    final cols = await d.customSelect("PRAGMA table_info(messages);").get();
    final hasReaction = cols.any((r) => r.read<String>('name') == 'my_reaction');
    final hasEditedAt = cols.any((r) => r.read<String>('name') == 'edited_at_ms');
    if (!hasReaction) {
      await d.customStatement('ALTER TABLE messages ADD COLUMN my_reaction TEXT;');
    }
    if (!hasEditedAt) {
      await d.customStatement('ALTER TABLE messages ADD COLUMN edited_at_ms INTEGER;');
    }

}

  Future<List<StoredChatMessage>> _loadLegacyMessagesFromNotes({
    required String contactId,
    required String conversationId,
  }) async {
    final d = database;
    final rows = await (d.select(d.contactNotes)
          ..where((t) => t.contactId.equals(contactId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAtMs, mode: OrderingMode.asc)]))
        .get();

    final out = <StoredChatMessage>[];
    for (final r in rows) {
      final body = r.body;
      if (!body.startsWith(_msgPrefix)) continue;
      try {
        final obj = jsonDecode(body);
        if (obj is! Map) continue;
        if (obj['t'] != 'msg') continue;
        if (obj['cid'] != conversationId) continue;

        out.add(
          StoredChatMessage(
            id: r.id,
            createdAtMs: r.createdAtMs,
            text: (obj['text'] ?? '').toString(),
            isOutgoing: obj['out'] == true,
          ),
        );
      } catch (_) {}
    }
    return out;
  }


  /// Загрузить контакты из БД.
  Future<List<models.Contact>> loadContacts() async {
    final d = database;
    final contactRows = await d.select(d.contacts).get();
    if (contactRows.isEmpty) return const [];

    final channels = await d.select(d.contactChannels).get();
    final labels = await d.select(d.contactLabels).get();
    final notes = await d.select(d.contactNotes).get();

    final byId = <String, models.Contact>{};
    for (final r in contactRows) {
      byId[r.id] = models.Contact(
        id: r.id,
        displayName: r.displayName,
        // В БД эти поля могут быть null, а в наших моделях они не-null.
        // Держим пустую строку вместо null.
        firstName: r.firstName ?? '',
        lastName: r.lastName ?? '',
        company: r.company ?? '',
        channels: <models.ContactChannel>[],
        labels: <String>{},
        notes: <models.ContactNote>[],
      );
    }

    for (final ch in channels) {
      final c = byId[ch.contactId];
      if (c == null) continue;
      final src = MessageSourceExt.tryParse(ch.source);
      if (src == null) continue;
      c.channels.add(models.ContactChannel(source: src, handle: ch.handle, isPrimary: ch.isPrimary));
    }

    for (final lb in labels) {
      final c = byId[lb.contactId];
      if (c == null) continue;
      if (!c.labels.contains(lb.labelName)) c.labels.add(lb.labelName);
    }

    for (final n in notes) {
      final c = byId[n.contactId];
      if (c == null) continue;
      c.notes.add(models.ContactNote(id: n.id, createdAt: DateTime.fromMillisecondsSinceEpoch(n.createdAtMs), text: n.body));
    }

    for (final c in byId.values) {
      c.notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return byId.values.toList();
  }

  Future<List<Conversation>> loadConversations() async {
    final d = database;
    final convRows = await d.select(d.conversationsTable).get();
    if (convRows.isEmpty) return const [];

    final ids = convRows.map((r) => r.id).toList(growable: false);
    final unread = await _loadUnreadCountsForConversationIds(ids);

    return convRows
        .map(
          (r) => Conversation(
            id: r.id,
            contactId: r.contactId,
            source: MessageSourceExt.parse(r.source),
            handle: r.handle,
            lastMessage: r.lastMessage,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAtMs),
            unreadCount: unread[r.id] ?? 0,
          ),
        )
        .toList();
  }

  Future<Map<String, int>> _loadUnreadCountsForConversationIds(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final d = database;
    await _ensureConversationStateTable();

    // Build "?, ?, ?" placeholders safely
    final placeholders = List.filled(ids.length, '?').join(', ');
    final vars = ids.map((e) => Variable<String>(e)).toList(growable: false);

    final rows = await d.customSelect(
      'SELECT conversation_id, unread_count FROM conversation_state WHERE conversation_id IN ($placeholders)',
      variables: vars,
    ).get();

    final out = <String, int>{};
    for (final r in rows) {
      final id = r.read<String>('conversation_id');
      final cnt = r.read<int>('unread_count');
      out[id] = cnt;
    }
    return out;
  }

  Future<void> setUnreadCount({
    required String conversationId,
    required int unreadCount,
    int? lastReadMs,
  }) async {
    final d = database;
    await _ensureConversationStateTable();
    final lr = lastReadMs ?? DateTime.now().millisecondsSinceEpoch;

    await d.customStatement(
      'INSERT INTO conversation_state(conversation_id, unread_count, last_read_ms) VALUES (?, ?, ?) '
      'ON CONFLICT(conversation_id) DO UPDATE SET unread_count = excluded.unread_count, last_read_ms = excluded.last_read_ms',
      [conversationId, unreadCount, lr],
    );
  }

  Future<int> getUnreadCount(String conversationId) async {
    final d = database;
    await _ensureConversationStateTable();
    final rows = await d.customSelect(
      'SELECT unread_count FROM conversation_state WHERE conversation_id = ?',
      variables: [Variable<String>(conversationId)],
    ).get();
    if (rows.isEmpty) return 0;
    return rows.first.read<int>('unread_count');
  }


  // -------------------- writes --------------------

  Future<void> upsertContact(models.Contact c) async {
    final d = database;
    await d.into(d.contacts).insertOnConflictUpdate(
          db.ContactsCompanion.insert(
            id: c.id,
            displayName: c.displayName,
            firstName: Value(c.firstName),
            lastName: Value(c.lastName),
            company: Value(c.company),
          ),
        );

    // Переписываем дочерние таблицы целиком для контакта (просто и надежно).
    await (d.delete(d.contactChannels)..where((t) => t.contactId.equals(c.id))).go();
    for (final ch in c.channels) {
      await d.into(d.contactChannels).insert(
            db.ContactChannelsCompanion.insert(
              contactId: c.id,
              source: ch.source.name,
              handle: ch.handle,
              isPrimary: Value(ch.isPrimary),
            ),
          );
    }

    await (d.delete(d.contactLabels)..where((t) => t.contactId.equals(c.id))).go();
    for (final label in c.labels) {
      await d.into(d.contactLabels).insert(
            db.ContactLabelsCompanion.insert(contactId: c.id, labelName: label),
          );
    }

    await (d.delete(d.contactNotes)..where((t) => t.contactId.equals(c.id))).go();
    for (final n in c.notes) {
      await d.into(d.contactNotes).insert(
            db.ContactNotesCompanion.insert(
              id: n.id,
              contactId: c.id,
              createdAtMs: n.createdAt.millisecondsSinceEpoch,
              body: n.text,
            ),
          );
    }
  }

  
  Future<void> upsertConversation(Conversation c) async {
    final d = database;
    await d.into(d.conversationsTable).insertOnConflictUpdate(
          db.ConversationsTableCompanion.insert(
            id: c.id,
            contactId: c.contactId,
            source: c.source.name,
            handle: c.handle,
            lastMessage: c.lastMessage,
            updatedAtMs: c.updatedAt.millisecondsSinceEpoch,
          ),
        );
  }

  // ---------------------------------------------------------------------------
  // Сообщения (MVP)
  //
  // Важно: сейчас мы НЕ меняем схему БД (Drift codegen), поэтому храним сообщения
  // в таблице ContactNotes как JSON, помечая их типом "msg".
  //
  // Пример body:
  // {"t":"msg","cid":"<conversationId>","out":true,"text":"Привет"}
  // ---------------------------------------------------------------------------

  static const String _msgPrefix = '{"t":"msg"';

  Future<void> addMessage({
    required String contactId,
    required String conversationId,
    required bool isOutgoing,
    required String text,
    int? createdAtMs,
  }) async {
    await _ensureMessagesTable();
    final d = database;
    final ts = createdAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final id = 'msg_${conversationId}_$ts';

    await d.customStatement(
      'INSERT OR REPLACE INTO messages(id, conversation_id, contact_id, is_outgoing, text, created_at_ms, my_reaction) VALUES(?, ?, ?, ?, ?, ?, ?);',
      [id, conversationId, contactId, isOutgoing ? 1 : 0, text, ts, null],
    );

    // Старый способ (через ContactNotes) оставляем только для обратной совместимости в чтении.
  }

  

Future<void> editMessage({
  required String messageId,
  required String newText,
  int? editedAtMs,
}) async {
  await _ensureMessagesTable();
  final d = database;
  final ts = editedAtMs ?? DateTime.now().millisecondsSinceEpoch;
  await d.customStatement(
    'UPDATE messages SET text = ?, edited_at_ms = ? WHERE id = ?;',
    [newText, ts, messageId],
  );
}

Future<void> setMessageReaction({
    required String messageId,
    String? reaction,
  }) async {
    await _ensureMessagesTable();
    final d = database;
    await d.customStatement(
      'UPDATE messages SET my_reaction = ? WHERE id = ?;',
      [reaction, messageId],
    );
  }

  

  Future<void> deleteMessage({required String messageId}) async {
    await _ensureMessagesTable();
    final d = database;
    await d.customStatement(
      'DELETE FROM messages WHERE id = ?',
      [messageId],
    );
  }

Future<List<StoredChatMessage>> loadMessages({
    required String contactId,
    required String conversationId,
  }) async {
    await _ensureMessagesTable();
    final d = database;

    final rows = await d.customSelect(
      'SELECT id, is_outgoing, text, created_at_ms, my_reaction, edited_at_ms FROM messages WHERE conversation_id = ? AND contact_id = ? ORDER BY created_at_ms ASC;',
      variables: [Variable<String>(conversationId), Variable<String>(contactId)],
    ).get();

    final out = <StoredChatMessage>[];
    for (final r in rows) {
      out.add(
        StoredChatMessage(
          id: r.read<String>('id'),
          createdAtMs: r.read<int>('created_at_ms'),
          text: r.read<String>('text'),
          isOutgoing: r.read<int>('is_outgoing') == 1,
            myReaction: (r.data.containsKey('my_reaction') ? r.read<String?>('my_reaction') : null),
          editedAtMs: (r.data.containsKey('edited_at_ms') ? r.read<int?>('edited_at_ms') : null),
        ),
      );
    }

    // Подхватываем старые сообщения, если они когда-то были сохранены в ContactNotes как JSON.
    // (Чтобы после апдейта история не пропала.)
    final legacy = await _loadLegacyMessagesFromNotes(contactId: contactId, conversationId: conversationId);
    out.addAll(legacy);

    out.sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
    return out;
  }
}


extension MessageSourceExt on MessageSource {
  static MessageSource parse(String name) {
    return MessageSource.values.firstWhere((e) => e.name == name, orElse: () => MessageSource.whatsapp);
  }

  static MessageSource? tryParse(String name) {
    for (final v in MessageSource.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}


class StoredChatMessage {
  final String id;
  final int createdAtMs;
  final String text;
  final bool isOutgoing;
  final String? myReaction;
  final int? editedAtMs;

  const StoredChatMessage({
    required this.id,
    required this.createdAtMs,
    required this.text,
    required this.isOutgoing,
    this.myReaction,
    this.editedAtMs,
  });
}
