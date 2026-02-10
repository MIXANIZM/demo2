import 'package:flutter/material.dart';
import 'navigation/home_page.dart';

void main() {
  runApp(const MessengerCrmApp());
}

class MessengerCrmApp extends StatelessWidget {
  const MessengerCrmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Messenger CRM',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      home: const HomeShell(),
    );
  }
}
