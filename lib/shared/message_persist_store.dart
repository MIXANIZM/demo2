import 'dart:async';

import 'package:flutter/foundation.dart';

import 'conversation_store.dart';
import 'message_models.dart';
import 'message_storage.dart';
import 'phone_utils.dart';
import 'message_source.dart';

/// In-memory store сообщений + сохранение в JSON.
///
/// Храним компактно: по умолчанию не больше _maxPerConversation сообщений на диалог.
class MessagePersistStore {
  MessagePersistStore._();
  static final MessagePersistStore instance = MessagePersistStore._();

  bool _loaded = false;

  final List<ChatMessage> _all = <ChatMessage>[];

  final ValueNotifier<int> version = ValueNotifier<int>(0);

  Timer? _flushTimer;

  static const int _maxPerConversation = 300;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    final json = await MessageStorage.instance.read();
    if (json == null) {
      _scheduleFlush();
      return;
    }

    try {
      final itemsJson = (json['messages'] as List?) ?? const [];
      _all
        ..clear()
        ..addAll(itemsJson.whereType<Map>().map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m))));

      // защита от разрастания
      _trimAll();
      version.value++;
    } catch (_) {
      _all.clear();
    }

    _scheduleFlush();
  }

  List<ChatMessage> forConversation(String conversationId) {
    return _all.where((m) => m.conversationId == conversationId).toList()
      ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
  }

  ChatMessage addIncomingText({
    required MessageSource source,
    required String handle,
    required String messageText,
    String? displayName,
  }) {
    final normalized = PhoneUtils.normalizeForHandle(handle);

    final conv = ConversationStore.instance.addIncomingMessage(
      source: source,
      handle: normalized,
      messageText: messageText,
      displayName: displayName,
    );

    final msg = ChatMessage(
      id: _newId(),
      conversationId: conv.id,
      contactId: conv.contactId,
      source: source,
      handle: normalized,
      fromMe: false,
      text: messageText,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      deliveryStatus: MessageDeliveryStatus.sent,
    );

    _all.add(msg);
    _trimConversation(conv.id);
    version.value++;
    _scheduleFlush();
    return msg;
  }

  ChatMessage addOutgoingText({
    required String conversationId,
    required String contactId,
    required MessageSource source,
    required String handle,
    required String text,
  }) {
    final normalized = PhoneUtils.normalizeForHandle(handle);

    final msg = ChatMessage(
      id: _newId(),
      conversationId: conversationId,
      contactId: contactId,
      source: source,
      handle: normalized,
      fromMe: true,
      text: text,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      deliveryStatus: MessageDeliveryStatus.sent,
    );

    _all.add(msg);
    _trimConversation(conversationId);
    version.value++;
    _scheduleFlush();

    // обновим превью диалога
    ConversationStore.instance.updatePreview(conversationId: conversationId, lastMessage: text);

    return msg;
  }

  void toggleLike(String messageId) {
    final m = _all.firstWhere((x) => x.id == messageId, orElse: () => ChatMessage(
      id: '', conversationId: '', contactId: '', source: MessageSource.whatsapp, handle: '', fromMe: false, text: '', createdAtMs: 0));
    if (m.id.isEmpty) return;
    m.liked = !m.liked;
    version.value++;
    _scheduleFlush();
  }

  void togglePin(String messageId) {
    final m = _all.firstWhere((x) => x.id == messageId, orElse: () => ChatMessage(
      id: '', conversationId: '', contactId: '', source: MessageSource.whatsapp, handle: '', fromMe: false, text: '', createdAtMs: 0));
    if (m.id.isEmpty) return;
    m.pinned = !m.pinned;
    version.value++;
    _scheduleFlush();
  }

  void deleteMessage(String messageId) {
    final m = _all.firstWhere((x) => x.id == messageId, orElse: () => ChatMessage(
      id: '', conversationId: '', contactId: '', source: MessageSource.whatsapp, handle: '', fromMe: false, text: '', createdAtMs: 0));
    if (m.id.isEmpty) return;
    m.isDeleted = true;
    version.value++;
    _scheduleFlush();
  }

  void forwardMessage({
    required String messageId,
    required String targetConversationId,
  }) {
    final m = _all.firstWhere((x) => x.id == messageId, orElse: () => ChatMessage(
      id: '', conversationId: '', contactId: '', source: MessageSource.whatsapp, handle: '', fromMe: false, text: '', createdAtMs: 0));
    if (m.id.isEmpty) return;

    final conv = ConversationStore.instance.tryGetById(targetConversationId);
    if (conv == null) return;

    final copied = ChatMessage(
      id: _newId(),
      conversationId: targetConversationId,
      contactId: conv.contactId,
      source: conv.source,
      handle: conv.handle,
      fromMe: true,
      text: m.isDeleted ? '' : m.text,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      forwardedFrom: 'Переслано',
      deliveryStatus: MessageDeliveryStatus.sent,
    );

    _all.add(copied);
    _trimConversation(targetConversationId);
    version.value++;
    _scheduleFlush();

    ConversationStore.instance.updatePreview(conversationId: targetConversationId, lastMessage: copied.text);
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 450), () async {
      await _flush();
    });
  }

  Future<void> _flush() async {
    final json = <String, dynamic>{
      'messages': _all.map((m) => m.toJson()).toList(),
    };
    await MessageStorage.instance.write(json);
  }

  void _trimAll() {
    final byConv = <String, List<ChatMessage>>{};
    for (final m in _all) {
      byConv.putIfAbsent(m.conversationId, () => <ChatMessage>[]).add(m);
    }
    final kept = <ChatMessage>[];
    for (final entry in byConv.entries) {
      entry.value.sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
      final list = entry.value;
      if (list.length <= _maxPerConversation) {
        kept.addAll(list);
      } else {
        kept.addAll(list.sublist(list.length - _maxPerConversation));
      }
    }
    _all
      ..clear()
      ..addAll(kept);
  }

  void _trimConversation(String conversationId) {
    final list = _all.where((m) => m.conversationId == conversationId).toList()
      ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
    if (list.length <= _maxPerConversation) return;

    final keep = list.sublist(list.length - _maxPerConversation).map((m) => m.id).toSet();
    _all.removeWhere((m) => m.conversationId == conversationId && !keep.contains(m.id));
  }
}
