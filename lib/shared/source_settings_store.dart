import 'package:flutter/foundation.dart';

import 'message_source.dart';

/// Настройки источников (пока in-memory).
///
/// Цель: заранее зафиксировать "точку правды" для того,
/// какие источники включены, и какой у них статус подключения.
/// Позже реальные бриджи будут обновлять эти статусы, а UI не меняется.
enum SourceConnectionStatus { disconnected, connecting, connected, error }

extension SourceConnectionStatusUi on SourceConnectionStatus {
  String get label {
    switch (this) {
      case SourceConnectionStatus.disconnected:
        return 'Не подключено';
      case SourceConnectionStatus.connecting:
        return 'Подключение…';
      case SourceConnectionStatus.connected:
        return 'Подключено';
      case SourceConnectionStatus.error:
        return 'Ошибка';
    }
  }
}

class SourceSettingsStore {
  SourceSettingsStore._();

  static final SourceSettingsStore instance = SourceSettingsStore._();

  /// Включенные источники (участвуют в фильтрах/моках и в приёме событий).
  final ValueNotifier<Set<MessageSource>> enabled = ValueNotifier<Set<MessageSource>>({
    MessageSource.telegram,
    MessageSource.whatsapp,
    MessageSource.sms,
    MessageSource.instagram,
  });

  /// Статусы подключения источников (заглушка, но интерфейс уже готов).
  final ValueNotifier<Map<MessageSource, SourceConnectionStatus>> connectionStatus =
      ValueNotifier<Map<MessageSource, SourceConnectionStatus>>({
    MessageSource.telegram: SourceConnectionStatus.disconnected,
    MessageSource.whatsapp: SourceConnectionStatus.disconnected,
    MessageSource.sms: SourceConnectionStatus.disconnected,
    MessageSource.instagram: SourceConnectionStatus.disconnected,
  });

  /// Последняя ошибка подключения (если была).
  final ValueNotifier<Map<MessageSource, String?>> lastError = ValueNotifier<Map<MessageSource, String?>>({
    MessageSource.telegram: null,
    MessageSource.whatsapp: null,
    MessageSource.sms: null,
    MessageSource.instagram: null,
  });

  bool isEnabled(MessageSource s) => enabled.value.contains(s);


  /// Список включённых источников в стабильном порядке (удобно для UI).
  List<MessageSource> enabledList() {
    const order = <MessageSource>[
      MessageSource.telegram,
      MessageSource.whatsapp,
      MessageSource.sms,
      MessageSource.instagram,
    ];
    return order.where(isEnabled).toList();
  }


  void setEnabled(MessageSource s, bool value) {
    final next = {...enabled.value};
    if (value) {
      next.add(s);
    } else {
      next.remove(s);
    }
    enabled.value = next;
  }

  SourceConnectionStatus statusOf(MessageSource s) => connectionStatus.value[s] ?? SourceConnectionStatus.disconnected;

  void setStatus(MessageSource s, SourceConnectionStatus status, {String? error}) {
    final next = {...connectionStatus.value};
    next[s] = status;
    connectionStatus.value = next;

    if (status == SourceConnectionStatus.error) {
      final e = {...lastError.value};
      e[s] = (error ?? 'Неизвестная ошибка');
      lastError.value = e;
    } else if (status == SourceConnectionStatus.connected || status == SourceConnectionStatus.disconnected) {
      final e = {...lastError.value};
      e[s] = null;
      lastError.value = e;
    }
  }
}
