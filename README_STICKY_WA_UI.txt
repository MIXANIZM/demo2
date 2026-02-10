КАК ПОДКЛЮЧИТЬ ФОН ЧАТА (WhatsApp-like)

1) Скопируй папку assets/ в корень твоего Flutter-проекта (рядом с pubspec.yaml)
2) В pubspec.yaml добавь:

flutter:
  assets:
    - assets/chat_bg.png

3) flutter pub get

Флажок автответов (для теста) — в lib/features/chat/chat_page.dart:
const bool kEnableAutoReply = true;  // поставь false, когда не нужно

