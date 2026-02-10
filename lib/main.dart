import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'navigation/home_page.dart';
import 'shared/db_service.dart';
import 'shared/contact_store.dart';
import 'shared/conversation_store.dart';
import 'matrix/matrix_inbox_sync.dart';
import 'matrix/matrix_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DbService.instance.init();
  // Hydration: загружаем снапшот из БД в in-memory stores.
  final contacts = await DbService.instance.loadContacts();
  for (final c in contacts) {
    ContactStore.instance.putFromDb(c);
  }
  final conversations = await DbService.instance.loadConversations();
  if (conversations.isNotEmpty) {
    ConversationStore.instance.replaceAll(conversations);
  }
  // Matrix → Inbox adapter (read-only). Does nothing until Matrix is connected.
  MatrixInboxSync.instance.init();
  // Auto-connect Matrix session from saved credentials/token (non-blocking).
  // This makes Inbox refresh automatically without pressing "Connect" each time.
  unawaited(MatrixService.instance.autoConnectFromSaved());

  runApp(const ProviderScope(child: MessengerCrmApp()));
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