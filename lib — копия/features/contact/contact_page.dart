import 'package:flutter/material.dart';

class ContactPage extends StatelessWidget {
  final String name;

  const ContactPage({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Контакт')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const Text('Каналы: (позже добавим список)'),
            const SizedBox(height: 8),
            const Text('Ярлыки: (позже)'),
            const SizedBox(height: 8),
            const Text('Заметки: (позже)'),
          ],
        ),
      ),
    );
  }
}
