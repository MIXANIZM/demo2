import 'dart:async';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'message_models.dart';
import 'message_source.dart';
import 'message_storage.dart';

class MessageStore {
  MessageStore._();

  static final MessageStore instance = MessageStore._();

  final ValueNotifier<int> version = ValueNotifier<int>(0);


// Stream-обёртка над ValueNotifier, чтобы удобно подписываться как на "changes".
late final Stream<void> changes = (() {
  final controller = StreamController<void>.broadcast();
  void emit() => controller.add(null);
  version.addListener(emit);
  controller.onCancel = () {};
  return controller.stream;
})();

List<Message> listByConversation(String conversationId) => listForConversation(conversationId);

  /// convId -> messages (sorted asc by createdAtMs)
  final Map<String, List<Message>> _byConv = {};

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await MessageStorage.instance.read();
    if (raw == null) return;

    final items = raw['messages'];
    if (items is List) {
      for (final it in items) {
        if (it is Map<String, dynamic>) {
          final m = Message.fromJson(it);
          if (m.id.isEmpty || m.conversationId.isEmpty) continue;
          (_byConv[m.conversationId] ??= []).add(m);
        }
      }
      for (final e in _byConv.entries) {
        e.value.sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
      }
      version.value++;
    }
  }

  List<Message> listForConversation(String convId) {
    return List.unmodifiable(_byConv[convId] ?? const <Message>[]);
  }

  Future<void> addMessage({
    required String conversationId,
    required MessageSource source,
    required String handle,
    required MessageDirection direction,
    required String text,
  }) async {
    await ensureLoaded();
    final m = Message(
      id: makeMessageId(),
      conversationId: conversationId,
      source: source,
      handle: handle,
      direction: direction,
      text: text,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    (_byConv[conversationId] ??= []).add(m);
    version.value++;
    await _persist();
  }

  Future<void> toggleLike(String conversationId, String messageId) async {
    await ensureLoaded();
    final list = _byConv[conversationId];
    if (list == null) return;
    final m = list.where((x) => x.id == messageId).cast<Message?>().firstWhere((x) => true, orElse: () => null);
    if (m == null) return;
    m.liked = !m.liked;
    version.value++;
    await _persist();
  }

  Future<void> togglePin(String conversationId, String messageId) async {
    await ensureLoaded();
    final list = _byConv[conversationId];
    if (list == null) return;
    final idx = list.indexWhere((x) => x.id == messageId);
    if (idx < 0) return;
    list[idx].isPinned = !list[idx].isPinned;
    version.value++;
    await _persist();
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    await ensureLoaded();
    final list = _byConv[conversationId];
    if (list == null) return;
    final idx = list.indexWhere((x) => x.id == messageId);
    if (idx < 0) return;
    list[idx].isDeleted = true;
    version.value++;
    await _persist();
  }

  Future<void> _persist() async {
    final all = <Map<String, dynamic>>[];
    for (final e in _byConv.entries) {
      for (final m in e.value) {
        all.add(m.toJson());
      }
    }
    await MessageStorage.instance.write({'messages': all});
  }
}
