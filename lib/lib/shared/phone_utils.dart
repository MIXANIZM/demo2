class PhoneUtils {
  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static bool looksLikePhone(String input) {
    final digits = _digitsOnly(input);
    return digits.length >= 9;
  }

  /// Normalize common Russian phone formats to +7XXXXXXXXXX.
  /// Returns '' if not possible.
  static String normalizeRuPhone(String input) {
    var digits = _digitsOnly(input);
    if (digits.isEmpty) return '';

    // 0079XXXXXXXXXX -> 79XXXXXXXXXX
    if (digits.startsWith('007') && digits.length == 13) {
      digits = digits.substring(2); // drop leading "00"
    }

    // 9011111111 -> 79011111111
    if (digits.length == 10 && digits.startsWith('9')) {
      digits = '7$digits';
    }

    // 89011111111 -> 79011111111
    if (digits.length == 11 && digits.startsWith('8')) {
      digits = '7${digits.substring(1)}';
    }

    // 79011111111
    if (digits.length == 11 && digits.startsWith('7')) {
      return '+$digits';
    }

    return '';
  }

  /// If input looks like RU phone, returns normalized +7XXXXXXXXXX, else trimmed input.
  static String normalizeForHandle(String input) {
    final n = normalizeRuPhone(input);
    return n.isNotEmpty ? n : input.trim();
  }
}
