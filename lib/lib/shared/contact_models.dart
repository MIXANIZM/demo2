import 'package:flutter/material.dart';

import 'message_source.dart';

/// Единый контакт (один человек) с несколькими каналами.
///
/// Принцип: модели — простые. Никаких провайдеров/слоёв.
class Contact {
  final String id;
  String displayName;
  String firstName;
  String lastName;
  String company;
  final List<ContactChannel> channels;
  final Set<String> labels; // CRM-ярлыки контакта (пока без UI редактирования)
  final List<ContactNote> notes; // заметки контакта

  Contact({
    required this.id,
    required this.displayName,
    this.firstName = '',
    this.lastName = '',
    this.company = '',
    List<ContactChannel>? channels,
    Set<String>? labels,
    List<ContactNote>? notes,
  })  : channels = channels ?? <ContactChannel>[],
        labels = labels ?? <String>{},
        notes = notes ?? <ContactNote>[];
}

extension ContactDisplay on Contact {
  String get fullName {
    final f = firstName.trim();
    final l = lastName.trim();
    final n = [f, l].where((e) => e.isNotEmpty).join(' ');
    return n;
  }

  String get preferredTitle {
    final n = fullName;
    return n.isNotEmpty ? n : displayName;
  }
}

class ContactChannel {
  final MessageSource source;
  final String handle; // телефон, @username, и т.д.
  final bool isPrimary;

  ContactChannel({
    required this.source,
    required this.handle,
    this.isPrimary = false,
  });
}

class ContactNote {
  final String id;
  final DateTime createdAt;
  String text;

  ContactNote({
    required this.id,
    required this.createdAt,
    required this.text,
  });
}

/// UI-хелпер для кружка канала в карточке контакта.
class ChannelDot extends StatelessWidget {
  final MessageSource source;
  final double size;

  const ChannelDot({super.key, required this.source, this.size = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: source.color, shape: BoxShape.circle),
    );
  }
}
