import 'package:flutter/foundation.dart';

class MatrixUiLogger {
  MatrixUiLogger._();
  static final MatrixUiLogger instance = MatrixUiLogger._();

  final ValueNotifier<String> listenable = ValueNotifier<String>('');
  String get text => listenable.value;

  void clear() => listenable.value = '';

  void log(String message) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final line = '[$ts] $message';

    final current = listenable.value;
    final next = current.isEmpty ? line : '$current\n$line';

    // Keep last ~300 lines by cutting from the top (cheap heuristic by char count)
    if (next.length > 20000) {
      // cut first ~1/3
      final cut = next.indexOf('\n', next.length ~/ 3);
      listenable.value = cut > 0 ? next.substring(cut + 1) : next;
    } else {
      listenable.value = next;
    }
  }
}
