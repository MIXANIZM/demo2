import 'message_source.dart';
import 'source_settings_store.dart';
import 'conversation_store.dart';
import 'phone_utils.dart';

/// Единая точка входа для входящих событий (пока — из моков).
///
/// Позже реальные бриджи (Telegram/WhatsApp/SMS/Instagram) должны
/// вызывать только этот шлюз. Он:
/// - нормализует handle (телефон)
/// - учитывает включенность источника
/// - передаёт событие в ConversationStore (который уже гарантирует getOrCreateForIncoming)
class IncomingGateway {
  IncomingGateway._();

  static final IncomingGateway instance = IncomingGateway._();

  void receive({
    required MessageSource source,
    required String handle,
    required String messageText,
    String? displayName,
  }) {
    // Если источник выключен — игнорируем событие (для моков и будущих бриджей).
    if (!SourceSettingsStore.instance.isEnabled(source)) return;

    final normalizedHandle = PhoneUtils.normalizeForHandle(handle);
    ConversationStore.instance.addIncomingMessage(
      source: source,
      handle: normalizedHandle,
      messageText: messageText,
      displayName: displayName,
    );
  }
}
