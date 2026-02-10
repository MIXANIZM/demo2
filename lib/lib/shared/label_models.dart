import 'package:flutter/material.dart';

/// CRM-ярлык (используем и для фильтрации входящих, и для ярлыков контакта).
///
/// Важно: один единственный класс, чтобы не было "разных типов" из-за дублей.
class LabelItem {
  String name;
  Color color;

  LabelItem({required this.name, required this.color});
}
