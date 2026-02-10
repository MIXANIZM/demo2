import 'message_source.dart';

/// Диалог (переписка) в агрегаторе.
///
/// Важно: ярлыков у диалога отдельно НЕТ — они живут у контакта.
/// Диалог хранит только ссылку на contactId + канал (source/handle).
class Conversation {
  final String id;

  /// На какого человека (Contact) ссылается диалог.
  String contactId;

  /// Канал/источник (Telegram/WhatsApp/SMS/Instagram).
  final MessageSource source;

  /// Handle канала: телефон или @username.
  final String handle;

  /// Последнее сообщение (превью).
  String lastMessage;

  /// Время последнего обновления.
  DateTime updatedAt;

  /// Непрочитанные (пока заглушка).
  int unreadCount;

  Conversation({
    required this.id,
    required this.contactId,
    required this.source,
    required this.handle,
    required this.lastMessage,
    required this.updatedAt,
    this.unreadCount = 0,
  });
}
