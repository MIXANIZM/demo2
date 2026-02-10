import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

enum MessageSource { all, telegram, whatsapp, sms, instagram, matrix }

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
      case MessageSource.matrix:
        return 'Matrix';
    }
  }

  IconData get icon {
    switch (this) {
      case MessageSource.all:
        return FontAwesomeIcons.layerGroup;
      case MessageSource.telegram:
        return FontAwesomeIcons.telegram;
      case MessageSource.whatsapp:
        return FontAwesomeIcons.whatsapp;
      case MessageSource.sms:
        return FontAwesomeIcons.commentSms;
      case MessageSource.instagram:
        return FontAwesomeIcons.instagram;
      case MessageSource.matrix:
        return FontAwesomeIcons.server;
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
      case MessageSource.matrix:
        return const Color(0xFF0DBD8B);
    }
  }
}
