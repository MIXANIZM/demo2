import 'package:url_launcher/url_launcher.dart';

import 'phone_utils.dart';

/// Открывает внешний чат по номеру телефона (без привязки к room_id).
/// Сейчас это "внешний запуск" WhatsApp/Telegram, как в Easy Message.
/// Позже можно заменить на создание/поиск Matrix-room через мост.
class ExternalChatLauncher {
  static String _digitsOnly(String input) => input.replaceAll(RegExp(r'\D'), '');

  static Future<bool> openWhatsApp(String phoneInput) async {
    final normalized = PhoneUtils.normalizeRuPhone(phoneInput);
    final digits = _digitsOnly(normalized);
    if (digits.isEmpty) return false;

    try {
      final url = Uri.parse('https://wa.me/$digits');
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openTelegram(String phoneInput) async {
    final normalized = PhoneUtils.normalizeRuPhone(phoneInput);
    final digits = _digitsOnly(normalized);
    if (digits.isEmpty) return false;

    // 1) Попытка через tg:// (может работать на части устройств/клиентов)
    try {
      // 1) Попытка через tg:// (может работать на части устройств/клиентов)
      final tgScheme = Uri.parse('tg://resolve?phone=$digits');
      final canTg = await canLaunchUrl(tgScheme);
      if (canTg) {
        return await launchUrl(tgScheme, mode: LaunchMode.externalApplication);
      }

      // 2) Фоллбек: открыть Telegram app/веб и дать пользователю продолжить вручную
      final web = Uri.parse('https://t.me/+${digits}');
      return await launchUrl(web, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
