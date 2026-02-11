import 'dart:async';

import 'package:flutter/foundation.dart';

import 'conversation_models.dart';
import 'contact_models.dart';
import 'contact_store.dart';
import 'db_service.dart';
import 'message_source.dart';
import 'phone_utils.dart';

/// Максимально простой in-memory store для диалогов.
///
/// Ключевое правило проекта:
/// ❗ любой новый входящий диалог всегда проходит через ContactStore.getOrCreateForIncoming.
class ConversationStore {
  ConversationStore._();

  static final ConversationStore instance = ConversationStore._();

  final List<Conversation> _conversations = <Conversation>[];

  /// Простейший способ уведомлять UI без провайдеров.
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  List<Conversation> get all => List<Conversation>.unmodifiable(_conversations);

  /// Заменить весь список (используется для гидрации из БД).
  void replaceAll(List<Conversation> items) {
    _conversations
      ..clear()
      ..addAll(items);
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    // Важно для UI: если в БД есть диалоги, но контакт ещё не загружен/не связан,
    // Inbox может не показать ярлыки до тех пор, пока контакт не будет создан/обновлён.
    // Здесь гарантируем, что для каждого диалога есть контакт в ContactStore.
    for (final convItem in _conversations) {
      final hasContact = ContactStore.instance.tryGet(convItem.contactId) != null;
      if (hasContact) continue;

      // Пытаемся восстановить контакт по каналу/handle (или создаём новый).
      final c = ContactStore.instance.getOrCreateForIncoming(
        source: convItem.source,
        handle: convItem.handle,
        displayName: convItem.handle,
      );
      convItem.contactId = c.id;
      unawaited(DbService.instance.upsertConversation(convItem));
    }
    version.value++;
  }

  Conversation? tryGet(String id) {
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Добавить/обновить входящее сообщение.
  ///
  /// - создаёт контакт (или находит существующий) через getOrCreateForIncoming
  /// - создаёт диалог (или находит существующий) по (source+handle)
  /// - обновляет lastMessage/updatedAt
  Conversation addIncomingMessage({
    required MessageSource source,
    required String handle,
    required String messageText,
    String? displayName,
  }) {
    final normalizedHandle = PhoneUtils.normalizeForHandle(handle);
    final contact = ContactStore.instance.getOrCreateForIncoming(
      source: source,
      handle: normalizedHandle,
      displayName: displayName,
    );

    final normalized = normalizedHandle;
    final existing = _conversations.cast<Conversation?>().firstWhere(
          (c) => c != null && c.source == source && c.handle.toLowerCase() == normalized.toLowerCase(),
          orElse: () => null,
        );

    if (existing != null) {
      // Если раньше было приклеено к другому контакту — обновим ссылку.
      if (existing.contactId != contact.id) {
        existing.contactId = contact.id;
      }
      existing.lastMessage = messageText;
      existing.updatedAt = DateTime.now();
      // Move conversation to top on new activity
      _conversations.remove(existing);
      _conversations.insert(0, existing);
      existing.unreadCount = existing.unreadCount + 1;
      unawaited(DbService.instance.setUnreadCount(conversationId: existing.id, unreadCount: existing.unreadCount));
      version.value++;
      unawaited(DbService.instance.upsertConversation(existing));
      return existing;
    }

    final conv = Conversation(
      id: _newId(),
      contactId: contact.id,
      source: source,
      handle: normalized,
      lastMessage: messageText,
      updatedAt: DateTime.now(),
      unreadCount: 1,
    );

    _conversations.insert(0, conv);
    version.value++;
    unawaited(DbService.instance.upsertConversation(conv));
    unawaited(DbService.instance.setUnreadCount(conversationId: conv.id, unreadCount: conv.unreadCount));
    return conv;
  }

  /// Ensure a conversation exists for a given channel.
  /// Useful when we create a contact manually from search, before real sources are connected.
  Conversation ensureConversation({
    required MessageSource source,
    required String handle,
    required String contactId,
    String lastMessage = 'Контакт создан',
  }) {
    final normalized = PhoneUtils.normalizeForHandle(handle);
    final existing = _conversations.cast<Conversation?>().firstWhere(
          (c) => c != null && c.source == source && c.handle.toLowerCase() == normalized.toLowerCase(),
          orElse: () => null,
        );

    if (existing != null) {
      if (existing.contactId != contactId) {
        existing.contactId = contactId;
      }
      existing.lastMessage = lastMessage;
      existing.updatedAt = DateTime.now();
      version.value++;
      unawaited(DbService.instance.upsertConversation(existing));
      return existing;
    }

    final conv = Conversation(
      id: _newId(),
      contactId: contactId,
      source: source,
      handle: normalized,
      lastMessage: lastMessage,
      updatedAt: DateTime.now(),
    );
    _conversations.insert(0, conv);
    version.value++;
    unawaited(DbService.instance.upsertConversation(conv));
    return conv;
  }


  /// Upsert a conversation preview without treating it as a new unread incoming message.
  /// Useful for external sync adapters (e.g., Matrix rooms mirrored into Inbox).
  ///
  /// - Does NOT increment unreadCount
  /// - Reorders to top only when updatedAt increases or preview changes
  Conversation upsertPreview({
    required MessageSource source,
    required String handle,
    required String contactId,
    required String lastMessage,
    required DateTime updatedAt,
  }) {
    final normalized = PhoneUtils.normalizeForHandle(handle);
    final existing = _conversations.cast<Conversation?>().firstWhere(
          (c) => c != null && c.source == source && c.handle.toLowerCase() == normalized.toLowerCase(),
          orElse: () => null,
        );

    if (existing != null) {
      bool changed = false;

      if (existing.contactId != contactId) {
        existing.contactId = contactId;
        changed = true;
      }

      if (existing.lastMessage != lastMessage) {
        existing.lastMessage = lastMessage;
        changed = true;
      }

      if (updatedAt.isAfter(existing.updatedAt)) {
        existing.updatedAt = updatedAt;
        changed = true;
      }

      if (changed) {
        // Move to top on real activity (newer timestamp or preview change)
        _conversations.remove(existing);
        _conversations.insert(0, existing);
        version.value++;
        unawaited(DbService.instance.upsertConversation(existing));
      }
      return existing;
    }

    final conv = Conversation(
      id: _newId(),
      contactId: contactId,
      source: source,
      handle: normalized,
      lastMessage: lastMessage,
      updatedAt: updatedAt,
      unreadCount: 0,
    );
    _conversations.insert(0, conv);
    version.value++;
    unawaited(DbService.instance.upsertConversation(conv));
    return conv;
  }

  /// Вручную привязать диалог к выбранному контакту.
  ///
  /// По умолчанию добавляет канал в контакт (source+handle).
    /// Вручную привязать диалог к выбранному контакту.
  ///
  /// По умолчанию добавляет канал в контакт (source+handle).
  Future<void> linkConversationToContact(
    String conversationId,
    String contactId, {
    bool alsoUpsertChannel = true,
  }) async {
    final conv = tryGet(conversationId);
    if (conv == null) return;

    if (alsoUpsertChannel) {
      await ContactStore.instance.upsertChannel(
        contactId,
        source: conv.source,
        handle: conv.handle,
        makePrimary: false,
      );
    }

    // Для Matrix-диалогов handle обычно = room_id. Сохраняем явную привязку.
    if (conv.source == MessageSource.matrix) {
      await DbService.instance.linkRoomToContact(roomId: conv.handle, contactId: contactId);
    }

    conv.contactId = contactId;
    version.value++;
    await DbService.instance.upsertConversation(conv);
  }


  /// Создать новый контакт и привязать к нему диалог.
    /// Создать новый контакт и привязать к нему диалог.
  Future<Contact> createNewContactAndLink(String conversationId) async {
    final conv = tryGet(conversationId);
    if (conv == null) {
      throw StateError('Conversation not found: $conversationId');
    }

    final c = ContactStore.instance.getOrCreateForIncoming(
      source: conv.source,
      handle: conv.handle,
      displayName: conv.handle,
    );

    if (conv.source == MessageSource.matrix) {
      await DbService.instance.linkRoomToContact(roomId: conv.handle, contactId: c.id);
    }

    conv.contactId = c.id;
    version.value++;
    await DbService.instance.upsertConversation(conv);
    return c;
  }


  /// Демо-сид (чтобы UI не был пустым).


  
  /// Remove conversations matching predicate (in-memory only).
  /// Used for migrations / adapters (e.g. Matrix rooms mirrored as Telegram source).
  int removeWhere(bool Function(Conversation c) test) {
    final before = _conversations.length;
    _conversations.removeWhere(test);
    final removed = before - _conversations.length;
    if (removed > 0) {
      version.value++;
    }
    return removed;
  }

void markAsRead(String conversationId) {
    final c = _conversations.cast<Conversation?>().firstWhere(
          (x) => x != null && x.id == conversationId,
          orElse: () => null,
        );
    if (c == null) return;
    if (c.unreadCount == 0) return;
    c.unreadCount = 0;
    version.value++;
    unawaited(DbService.instance.setUnreadCount(conversationId: c.id, unreadCount: 0));
  }

  void markAsUnread(String conversationId, {int unreadCount = 1}) {
    final c = _conversations.cast<Conversation?>().firstWhere(
          (x) => x != null && x.id == conversationId,
          orElse: () => null,
        );
    if (c == null) return;
    c.unreadCount = unreadCount <= 0 ? 1 : unreadCount;
    version.value++;
    unawaited(DbService.instance.setUnreadCount(conversationId: c.id, unreadCount: c.unreadCount));
  }

void touchConversation(
  String conversationId, {
  String? lastMessage,
  DateTime? updatedAt,
  int? unreadCount,
}) {
  final c = _conversations.cast<Conversation?>().firstWhere(
        (x) => x != null && x.id == conversationId,
        orElse: () => null,
      );
  if (c == null) return;

  if (lastMessage != null) c.lastMessage = lastMessage;
  if (updatedAt != null) c.updatedAt = updatedAt;
  if (unreadCount != null) c.unreadCount = unreadCount;

  // Move to top to reflect most recent activity
  _conversations.remove(c);
  _conversations.insert(0, c);

  version.value++;

  // Persist minimal fields (DbService handles upsert)
  unawaited(DbService.instance.upsertConversation(c));
  if (unreadCount != null) {
    unawaited(DbService.instance.setUnreadCount(conversationId: c.id, unreadCount: c.unreadCount));
  }
}
  void ensureDemoSeed() {
    // Demo seed disabled.
  }


  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}