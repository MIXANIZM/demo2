import 'package:flutter/foundation.dart';

/// Минимальный стор настроек приложения.
/// Сейчас без персистентности (позже можно привязать к SharedPreferences/Hive).
class AppSettingsStore {
  AppSettingsStore._();

  static final AppSettingsStore instance = AppSettingsStore._();

  /// Если включено — при открытии чата пытаемся подгрузить всю историю автоматически.
  /// По умолчанию выключено, чтобы не тормозить работу.
  final ValueNotifier<bool> autoLoadFullHistory = ValueNotifier<bool>(false);
}
