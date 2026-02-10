import 'message_source.dart';

enum MessageDirection { incoming, outgoing }

class Message {
  final String id;
  final String conversationId;
  final MessageSource source;
  final String handle; // channel handle (phone, @username, etc)
  final MessageDirection direction;
  final String text;
  final int createdAtMs;

  bool isPinned;
  bool isDeleted;
  bool liked;

  Message({
    required this.id,
    required this.conversationId,
    required this.source,
    required this.handle,
    required this.direction,
    required this.text,
    required this.createdAtMs,
    this.isPinned = false,
    this.isDeleted = false,
    this.liked = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'source': messageSourceToId(source),
        'handle': handle,
        'direction': direction.name,
        'text': text,
        'createdAtMs': createdAtMs,
        'isPinned': isPinned,
        'isDeleted': isDeleted,
        'liked': liked,
      };

  static Message fromJson(Map<String, dynamic> j) {
    final src = messageSourceFromId(j['source'] as String? ?? 'wa');
    final dir = (j['direction'] == 'outgoing') ? MessageDirection.outgoing : MessageDirection.incoming;
    return Message(
      id: (j['id'] as String?) ?? '',
      conversationId: (j['conversationId'] as String?) ?? '',
      source: src,
      handle: (j['handle'] as String?) ?? '',
      direction: dir,
      text: (j['text'] as String?) ?? '',
      createdAtMs: (j['createdAtMs'] as num?)?.toInt() ?? 0,
      isPinned: (j['isPinned'] as bool?) ?? false,
      isDeleted: (j['isDeleted'] as bool?) ?? false,
      liked: (j['liked'] as bool?) ?? false,
    );
  }
}

String makeMessageId() => DateTime.now().microsecondsSinceEpoch.toString();

// Функции конвертации MessageSource <-> String
String messageSourceToId(MessageSource source) {
  switch (source) {
    case MessageSource.whatsapp:
      return 'wa';
    case MessageSource.telegram:
      return 'tg';
    case MessageSource.instagram:
      return 'ig';
    case MessageSource.vk:
      return 'vk';
    case MessageSource.facebook:
      return 'fb';
    case MessageSource.sms:
      return 'sms';
    case MessageSource.email:
      return 'email';
  }
}

MessageSource messageSourceFromId(String id) {
  switch (id) {
    case 'wa':
      return MessageSource.whatsapp;
    case 'tg':
      return MessageSource.telegram;
    case 'ig':
      return MessageSource.instagram;
    case 'vk':
      return MessageSource.vk;
    case 'fb':
      return MessageSource.facebook;
    case 'sms':
      return MessageSource.sms;
    case 'email':
      return MessageSource.email;
    default:
      return MessageSource.whatsapp; // fallback
  }
}