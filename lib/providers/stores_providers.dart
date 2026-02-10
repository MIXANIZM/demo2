import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/conversation_store.dart';
import '../shared/contact_store.dart';

final conversationStoreProvider = Provider<ConversationStore>((ref) {
  return ConversationStore.instance;
});

final contactStoreProvider = Provider<ContactStore>((ref) {
  return ContactStore.instance;
});


/// Триггеры пересборки UI по изменениям in-memory store.
/// Мы не меняем архитектуру стора (singleton), просто даём Riverpod-сигнал "данные обновились".
final conversationsVersionProvider = StreamProvider<int>((ref) {
  final store = ref.watch(conversationStoreProvider);

  final controller = StreamController<int>.broadcast();
  void listener() {
    if (!controller.isClosed) controller.add(store.version.value);
  }

  // initial
  controller.add(store.version.value);
  store.version.addListener(listener);

  ref.onDispose(() {
    store.version.removeListener(listener);
    controller.close();
  });

  return controller.stream;
});

final contactsVersionProvider = StreamProvider<int>((ref) {
  final store = ref.watch(contactStoreProvider);

  final controller = StreamController<int>.broadcast();
  void listener() {
    if (!controller.isClosed) controller.add(store.version.value);
  }

  controller.add(store.version.value);
  store.version.addListener(listener);

  ref.onDispose(() {
    store.version.removeListener(listener);
    controller.close();
  });

  return controller.stream;
});
