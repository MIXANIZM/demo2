import 'package:flutter/material.dart';

import '../../shared/source_settings_store.dart';
import 'sources_connections_page.dart';
import '../matrix_test/matrix_test_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    // В HomeShell уже есть общий Scaffold + AppBar
    final store = SourceSettingsStore.instance;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        const Text('Настройки', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),

        ValueListenableBuilder(
          valueListenable: store.enabled,
          builder: (context, enabled, _) {
            final count = (enabled as Set).length;
            return Card(
              child: ListTile(
                title: const Text('Источники и подключения', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text('Включено: $count'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SourcesConnectionsPage()),
                  );
                },
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        Card(
          child: ListTile(
            title: const Text('Matrix (тест)', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: const Text('Подключение по access token к твоему Synapse'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MatrixTestPage()),
              );
            },
          ),
        ),

        const Card(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Text(
              'Дальше здесь будут настройки приложения, уведомлений и интеграций. Пока держим минимально, чтобы не расползалось.',
              style: TextStyle(height: 1.3),
            ),
          ),
        ),
      ],
    );
  }
}
