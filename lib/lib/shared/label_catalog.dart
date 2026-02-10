import 'package:flutter/material.dart';

import 'label_models.dart';

/// Единый источник списка ярлыков для всего приложения.
///
/// Пока это in-memory, без сохранения.
class LabelCatalog {
  LabelCatalog._();
  static final LabelCatalog instance = LabelCatalog._();

  final List<LabelItem> _labels = <LabelItem>[
    LabelItem(name: 'Не оформлен', color: const Color(0xFF4FC3F7)),
    LabelItem(name: 'Новый заказ', color: const Color(0xFFFFD54F)),
    LabelItem(name: 'Ожидание платежа', color: const Color(0xFFFF8A65)),
    LabelItem(name: 'Оплачен', color: const Color(0xFFBA68C8)),
    LabelItem(name: 'Завершённый заказ', color: const Color(0xFF4DB6AC)),
    LabelItem(name: 'Самовывоз', color: const Color(0xFF90A4AE)),
    LabelItem(name: 'Курьер Яндекс', color: const Color(0xFF7986CB)),
  ];

  List<LabelItem> get labels => List<LabelItem>.from(_labels);

  void replaceAll(List<LabelItem> next) {
    _labels
      ..clear()
      ..addAll(next);
  }
}
