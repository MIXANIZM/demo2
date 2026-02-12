import '../matrix/matrix_service.dart';
import 'phone_utils.dart';

/// Создает/открывает чат через Matrix-мост (mautrix-*), без открытия внешних приложений.
///
/// Логика:
/// - Находим (или создаем) личную "комнату управления" с ботом моста (@telegrambot / @whatsappbot)
/// - Отправляем туда команду `pm <phone>`
/// - Мост приглашает в новую room-портал, где и идет переписка
///
/// Важно: для Telegram `pm <phone>` может работать только если номер доступен мосту
/// (например, есть в контактах Telegram-аккаунта или политика/настройки моста это разрешают).
class BridgeChatLauncher {
  /// Returns created portal room id if the bridge produced it during the timeout.
  static Future<String?> openTelegramByPhone(
    String phoneInput, {
    String? displayName,
    void Function(String stage)? onProgress,
  }) async {
    final normalized = PhoneUtils.normalizeRuPhone(phoneInput);
    if (normalized.isEmpty) return null;
    return await MatrixService.instance.createTelegramPortalByPhone(
      normalized,
      displayName: displayName,
      onProgress: onProgress,
    );
  }

  static Future<bool> openWhatsAppByPhone(String phoneInput) async {
    final normalized = PhoneUtils.normalizeRuPhone(phoneInput);
    if (normalized.isEmpty) return false;
    return await MatrixService.instance.startWhatsAppPmByPhone(normalized);
  }
}
