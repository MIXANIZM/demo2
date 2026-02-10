import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/message_source.dart';
import '../../shared/source_settings_store.dart';

class SourcesConnectionsPage extends StatefulWidget {
  const SourcesConnectionsPage({super.key});

  @override
  State<SourcesConnectionsPage> createState() => _SourcesConnectionsPageState();
}

class _SourcesConnectionsPageState extends State<SourcesConnectionsPage> {
  final store = SourceSettingsStore.instance;
  final Map<MessageSource, Timer?> _timers = {};

  @override
  void dispose() {
    for (final t in _timers.values) {
      t?.cancel();
    }
    super.dispose();
  }

  void _simulateConnect(MessageSource src) {
    // Если уже коннектимся — не дёргаем повторно.
    if (store.statusOf(src) == SourceConnectionStatus.connecting) return;

    store.setStatus(src, SourceConnectionStatus.connecting);

    _timers[src]?.cancel();
    _timers[src] = Timer(const Duration(milliseconds: 700), () {
      // Заглушка: считаем, что подключение прошло успешно.
      if (mounted) {
        store.setStatus(src, SourceConnectionStatus.connected);
      } else {
        store.setStatus(src, SourceConnectionStatus.connected);
      }
    });
  }

  void _disconnect(MessageSource src) {
    _timers[src]?.cancel();
    store.setStatus(src, SourceConnectionStatus.disconnected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Источники'),
      ),
      body: ValueListenableBuilder<Set<MessageSource>>(
        valueListenable: store.enabled,
        builder: (context, enabled, _) {
          return ValueListenableBuilder<Map<MessageSource, SourceConnectionStatus>>(
            valueListenable: store.connectionStatus,
            builder: (context, statuses, __) {
              return ValueListenableBuilder<Map<MessageSource, String?>>(
                valueListenable: store.lastError,
                builder: (context, errors, ___) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      const Text(
                        'Включай/выключай источники и смотри статус подключения. Пока это заглушка, но UI уже готов под реальные бриджи.',
                        style: TextStyle(height: 1.3),
                      ),
                      const SizedBox(height: 12),
                      for (final src in MessageSource.values) ...[
                        _SourceRow(
                          source: src,
                          enabled: enabled.contains(src),
                          status: statuses[src] ?? SourceConnectionStatus.disconnected,
                          errorText: errors[src],
                          onToggleEnabled: (v) => store.setEnabled(src, v),
                          onConnect: () => _simulateConnect(src),
                          onDisconnect: () => _disconnect(src),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.enabled,
    required this.status,
    required this.errorText,
    required this.onToggleEnabled,
    required this.onConnect,
    required this.onDisconnect,
  });

  final MessageSource source;
  final bool enabled;
  final SourceConnectionStatus status;
  final String? errorText;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final canConnect = enabled && (status == SourceConnectionStatus.disconnected || status == SourceConnectionStatus.error);
    final canDisconnect = status == SourceConnectionStatus.connected || status == SourceConnectionStatus.connecting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: source.color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(source.icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.label, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(status.label, style: TextStyle(color: Colors.black.withOpacity(0.6))),
                      if (status == SourceConnectionStatus.error && (errorText ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          errorText!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(value: enabled, onChanged: onToggleEnabled),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: canConnect ? onConnect : null,
                    child: const Text('Подключить'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: canDisconnect ? onDisconnect : null,
                    child: const Text('Отключить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
