import 'package:flutter/material.dart';

enum MessageSource { all, telegram, whatsapp, sms, instagram }

extension MessageSourceUi on MessageSource {
  bool get isAll => this == MessageSource.all;

  String get label {
    switch (this) {
      case MessageSource.all:
        return 'Все';
      case MessageSource.telegram:
        return 'Telegram';
      case MessageSource.whatsapp:
        return 'WhatsApp';
      case MessageSource.sms:
        return 'SMS';
      case MessageSource.instagram:
        return 'Instagram';
    }
  }

  IconData get icon {
    switch (this) {
      case MessageSource.all:
        return Icons.all_inbox;
      case MessageSource.telegram:
        return Icons.send;
      case MessageSource.whatsapp:
        return Icons.chat_bubble;
      case MessageSource.sms:
        return Icons.sms;
      case MessageSource.instagram:
        return Icons.camera_alt;
    }
  }

  Color get color {
    switch (this) {
      case MessageSource.all:
        return Colors.blueGrey;
      case MessageSource.telegram:
        return const Color(0xFF2AABEE);
      case MessageSource.whatsapp:
        return const Color(0xFF25D366);
      case MessageSource.sms:
        return const Color(0xFF607D8B);
      case MessageSource.instagram:
        return const Color(0xFFE1306C);
    }
  }
}
