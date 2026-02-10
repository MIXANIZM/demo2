import 'package:flutter/material.dart';
import '../contact/contact_page.dart';

class ChatPage extends StatelessWidget {
  final String name;

  const ChatPage({
    super.key,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ContactPage(name: name),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name),
              const Text(
                'Нажми для карточки контакта',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      body: const Center(
        child: Text(
          'Тут будет переписка',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
