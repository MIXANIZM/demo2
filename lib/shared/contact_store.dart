import 'dart:async';

import 'package:flutter/foundation.dart';

import 'contact_models.dart';
import 'message_source.dart';
import 'phone_utils.dart';
import 'db_service.dart';

/// Максимально простой in-memory store.
///
/// Сейчас нужен только для связи чат↔контакт без архитектурных наворотов.
class ContactStore {
  ContactStore._();

  static final ContactStore instance = ContactStore._();

  /// Версия стора для простого реактивного обновления UI (Riverpod/Consumer).
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  void _bump() {
    version.value++;
  }

  final Map<String, Contact> _byId = {};

  /// Индексы для автосвязывания контактов.
  ///
  /// - По телефону: позволяет склеивать WhatsApp/Telegram/SMS по одному номеру.
  /// - По (source+handle): на случай, когда handle не телефон (@username).
  final Map<String, String> _byPhoneKey = {}; // phoneKey -> contactId
  final Map<String, String> _byChannelKey = {}; // "source|handle" -> contactId

  List<Contact> get all => _byId.values.toList(growable: false);

  Contact? tryGet(String id) => _byId[id];

  /// Добавить контакт из БД (без побочных эффектов/сохранений).
  /// Используется только при старте приложения.
  void putFromDb(Contact contact) {
    _byId[contact.id] = contact;
    _reindexContact(contact);
    _bump();
  }

  Contact getOrCreate(Contact contact) {
    final c = _byId.putIfAbsent(contact.id, () => contact);
    _reindexContact(c);
    _persist(c);
    _bump();
    return c;
  }

  /// Главный метод для входящих сообщений:
  /// любой, кто написал → становится контактом.
  ///
  /// Автосвязь:
  /// - если handle похож на телефон, связываем контакты по телефону (между разными источниками)
  /// - иначе связываем по (source+handle)
  Contact getOrCreateForIncoming({
    required MessageSource source,
    required String handle,
    String? displayName,
  }) {
    final normalizedHandle = _normalizeHandle(handle);
    if (normalizedHandle.isEmpty) {
      // Защитный fallback: создадим «пустой» контакт.
      final c = Contact(id: _newId(), displayName: displayName?.trim().isNotEmpty == true ? displayName!.trim() : 'Неизвестный');
      _byId[c.id] = c;
      _reindexContact(c);
      _persist(c);
      _bump();
      return c;
    }

    final phoneKey = _extractPhoneKey(normalizedHandle);

    String? contactId;
    if (phoneKey != null) {
      contactId = _byPhoneKey[phoneKey];
    }

    contactId ??= _byChannelKey[_channelKey(source, normalizedHandle)];

    if (contactId != null) {
      final existing = _byId[contactId];
      if (existing != null) {
        // Канал мог отсутствовать — добавим.
        final hasChannel = existing.channels.any((ch) => ch.source == source && ch.handle == normalizedHandle);
        if (!hasChannel) {
          existing.channels.add(ContactChannel(source: source, handle: normalizedHandle, isPrimary: existing.channels.isEmpty));
        }

        // Если displayName задан и у контакта он выглядит как «голый телефон» — улучшим.
        final dn = displayName?.trim() ?? '';
        if (dn.isNotEmpty && existing.displayName.trim().isEmpty) {
          existing.displayName = dn;
        }

        _reindexContact(existing);
        _persist(existing);
        _bump();
        return existing;
      }
    }

    // Создаём новый.
    final c = Contact(
      id: _newId(),
      displayName: (displayName?.trim().isNotEmpty == true) ? displayName!.trim() : normalizedHandle,
      channels: [
        ContactChannel(source: source, handle: normalizedHandle, isPrimary: true),
      ],
    );
    _byId[c.id] = c;
    _reindexContact(c);
    _persist(c);
    _bump();
    return c;
  }

  /// Создать (или получить существующий) контакт по телефону.
  ///
  /// Важно: телефон приводим к +7XXXXXXXXXX.
  /// ВАЖНО: по умолчанию НЕ создаём Telegram-канал.
  /// Иначе получится "фейковый" Telegram по номеру телефона и сообщения могут уходить
  /// не туда, потому что реальный идентификатор Telegram-диалога у нас сейчас — Matrix room.
  Contact getOrCreateByPhone({
    required String phoneInput,
    bool addWhatsApp = true,
    bool addTelegram = false,
  }) {
    final normalizedPhone = PhoneUtils.normalizeRuPhone(phoneInput);
    if (normalizedPhone.isEmpty) {
      throw ArgumentError('Not a phone: $phoneInput');
    }

    final phoneKey = _extractPhoneKey(normalizedPhone);
    final existingId = phoneKey == null ? null : _byPhoneKey[phoneKey];
    if (existingId != null) {
      final existing = _byId[existingId];
      if (existing != null) {
        // Догарантируем наличие нужных каналов.
        if (addWhatsApp) {
          _ensureChannel(existing, MessageSource.whatsapp, normalizedPhone);
        }
        if (addTelegram) {
          _ensureChannel(existing, MessageSource.telegram, normalizedPhone);
        }
        _reindexContact(existing);
        _persist(existing);
        _bump();
        return existing;
      }
    }

    final channels = <ContactChannel>[];
    if (addWhatsApp) {
      channels.add(ContactChannel(source: MessageSource.whatsapp, handle: normalizedPhone, isPrimary: true));
    }
    if (addTelegram) {
      channels.add(ContactChannel(source: MessageSource.telegram, handle: normalizedPhone, isPrimary: channels.isEmpty));
    }
    if (channels.isEmpty) {
      channels.add(ContactChannel(source: MessageSource.whatsapp, handle: normalizedPhone, isPrimary: true));
    }

    final c = Contact(
      id: _newId(),
      displayName: normalizedPhone,
      channels: channels,
    );
    _byId[c.id] = c;
    _reindexContact(c);
    _persist(c);
    _bump();
    return c;
  }

  Future<void> updateContact(
    String contactId, {
    String? displayName,
    String? firstName,
    String? lastName,
    String? company,
  }
  ) async {
    final c = _byId[contactId];
    if (c == null) return;
    if (displayName != null) c.displayName = displayName;
    if (firstName != null) c.firstName = firstName;
    if (lastName != null) c.lastName = lastName;
    if (company != null) c.company = company;
    await _persistAsync(c);
    _bump();
  }

  Future<void> upsertChannel(
    String contactId, {
    required MessageSource source,
    required String handle,
    bool makePrimary = false,
  }
  ) async {
    final c = _byId[contactId];
    if (c == null) return;

    final normalized = _normalizeHandle(handle);
    if (normalized.isEmpty) return;
    // Автодобавление "телефонных" каналов:
    // Если добавили WhatsApp / Telegram / SMS с номером телефона — создаём такие же каналы
    // для остальных телефонных источников (кроме Instagram).
    const phoneSources = <MessageSource>{MessageSource.whatsapp, MessageSource.telegram, MessageSource.sms};
    final isPhoneHandle = PhoneUtils.looksLikePhone(normalized);

    // Если такой канал уже есть — обновим handle (по source).
    final idx = c.channels.indexWhere((ch) => ch.source == source);
    ContactChannel newCh = ContactChannel(source: source, handle: normalized, isPrimary: makePrimary);

    if (makePrimary) {
      // снять primary со всех
      c.channels.replaceRange(
        0,
        c.channels.length,
        c.channels.map((ch) => ContactChannel(source: ch.source, handle: ch.handle, isPrimary: false)),
      );
    }

    if (idx >= 0) {
      c.channels[idx] = newCh;
    } else {
      c.channels.add(newCh);
    }

    // Если это телефонный канал и handle похож на номер — добавим остальные телефонные каналы,
    // чтобы у контакта сразу были WA/TG/SMS с тем же номером (если их ещё нет).
    if (phoneSources.contains(source) && isPhoneHandle) {
      for (final other in phoneSources) {
        if (other == source) continue;
        final otherIdx = c.channels.indexWhere((ch) => ch.source == other);
        if (otherIdx >= 0) continue;
        c.channels.add(ContactChannel(source: other, handle: normalized, isPrimary: false));
      }
    }

    _reindexContact(c);
    await _persistAsync(c);
    _bump();
  }

  Future<void> removeChannel(String contactId, MessageSource source) async {
    final c = _byId[contactId];
    if (c == null) return;
    final wasPrimary = c.channels.any((ch) => ch.source == source && ch.isPrimary);
    c.channels.removeWhere((ch) => ch.source == source);
    if (wasPrimary && c.channels.isNotEmpty) {
      // сделать первый primary
      final first = c.channels.first;
      c.channels[0] = ContactChannel(source: first.source, handle: first.handle, isPrimary: true);
    }

    _reindexContact(c);
    await _persistAsync(c);
    _bump();
  }

  void setPrimaryChannel(String contactId, MessageSource source) {
    final c = _byId[contactId];
    if (c == null) return;
    if (c.channels.isEmpty) return;
    c.channels.replaceRange(
      0,
      c.channels.length,
      c.channels.map((ch) => ContactChannel(source: ch.source, handle: ch.handle, isPrimary: ch.source == source)),
    );

    _reindexContact(c);
    _persist(c);
  }

  /// Сделать конкретный канал (source+handle) основным.
  ///
  /// Важно: у одного контакта может быть несколько каналов одного source (например TG телефон и TG @username),
  /// поэтому первичность хранится на уровне channel, а не только source.
  void setPrimaryChannelByHandle(String contactId, MessageSource source, String handle) {
    final c = _byId[contactId];
    if (c == null) return;
    if (c.channels.isEmpty) return;

    final h = handle.trim();
    c.channels.replaceRange(
      0,
      c.channels.length,
      c.channels.map(
        (ch) => ContactChannel(
          source: ch.source,
          handle: ch.handle,
          isPrimary: ch.source == source && ch.handle.toLowerCase() == h.toLowerCase(),
        ),
      ),
    );

    _reindexContact(c);
    _persist(c);
  }


  /// Добавить заметку к контакту.
  Future<ContactNote> addNote(String contactId, String text) async {
    final c = _byId[contactId];
    if (c == null) {
      throw StateError('Contact not found: $contactId');
    }
    final note = ContactNote(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      text: text.trim(),
    );
    c.notes.insert(0, note);
    await _persistAsync(c);
    _bump();
    return note;
  }

  Future<void> deleteNote(String contactId, String noteId) async {
    final c = _byId[contactId];
    if (c == null) return;
    c.notes.removeWhere((n) => n.id == noteId);
    await _persistAsync(c);
    _bump();
  }

  Future<void> toggleLabel(String contactId, String labelName) async {
    final c = _byId[contactId];
    if (c == null) return;

    if (c.labels.contains(labelName)) {
      c.labels.remove(labelName);
    } else {
      c.labels.add(labelName);
    }

    // Важно: ждём запись в БД, чтобы ярлыки не терялись при быстром закрытии приложения.
    await DbService.instance.upsertContact(c);
    _bump();
  }

  /// Задать полный набор ярлыков для контакта (используется из Inbox bottom-sheet).
  /// Важно: ждём запись в БД, чтобы ярлыки не терялись при закрытии приложения.
  Future<void> setLabels(String contactId, Set<String> labels) async {
    final c = _byId[contactId];
    if (c == null) return;

    c.labels
      ..clear()
      ..addAll(labels);

    await DbService.instance.upsertContact(c);
    _bump();
  }

  /// Удобный метод: найти контакт по (канал+handle)
  Contact? findByChannel(MessageSource source, String handle) {
    final normalizedHandle = _normalizeHandle(handle);
    final id = _byChannelKey[_channelKey(source, normalizedHandle)];
    if (id == null) return null;
    return _byId[id];
  }

  // ----------------- helpers -----------------

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  String _normalizeHandle(String v) => PhoneUtils.normalizeForHandle(v);

  String _channelKey(MessageSource source, String handle) => '${source.name}|${handle.toLowerCase()}';

  /// Пытаемся вытащить «ключ телефона» из handle.
  ///
  /// Правило простое: если цифр >= 9 — считаем телефоном и склеиваем.
  /// Возвращаем только цифры (без +, пробелов, скобок).
  String? _extractPhoneKey(String handle) {
    final digits = handle.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9) return null;
    return digits;
  }

  void _ensureChannel(Contact c, MessageSource source, String handle) {
    final normalizedHandle = _normalizeHandle(handle);
    if (normalizedHandle.isEmpty) return;
    final idx = c.channels.indexWhere((ch) => ch.source == source);
    if (idx >= 0) {
      final wasPrimary = c.channels[idx].isPrimary;
      c.channels[idx] = ContactChannel(source: source, handle: normalizedHandle, isPrimary: wasPrimary);
    } else {
      c.channels.add(ContactChannel(source: source, handle: normalizedHandle, isPrimary: c.channels.isEmpty));
    }
  }

  void _reindexContact(Contact c) {
    // Удалять старые индексы точечно сложно без хранения обратных ссылок,
    // поэтому делаем простой, но безопасный способ: переиндексируем добавлением.
    for (final ch in c.channels) {
      final h = _normalizeHandle(ch.handle);
      if (h.isEmpty) continue;
      _byChannelKey[_channelKey(ch.source, h)] = c.id;
      final phoneKey = _extractPhoneKey(h);
      if (phoneKey != null) {
        _byPhoneKey[phoneKey] = c.id;
      }
    }
  }

  void _persist(Contact c) {
    // fire-and-forget, без await
    unawaited(DbService.instance.upsertContact(c));
  }

  Future<void> _persistAsync(Contact c) async {
    await DbService.instance.upsertContact(c);
  }



  

  /// Ensure a contact has a channel (source+handle). Used by Matrix bridge mapping to attach phone/username
  /// without breaking the existing roomId-based handle.
  void ensureChannel({
    required String contactId,
    required MessageSource source,
    required String handle,
    bool makePrimary = false,
  }) {
    final c = _byId[contactId];
    if (c == null) return;

    final normalizedHandle = _normalizeHandle(handle);
    if (normalizedHandle.isEmpty) return;

    final exists = c.channels.any((ch) => ch.source == source && ch.handle == normalizedHandle);
    if (exists) return;

    if (makePrimary) {
      // unset other primaries for this source
      for (var i = 0; i < c.channels.length; i++) {
        final ch = c.channels[i];
        if (ch.source == source && ch.isPrimary) {
          c.channels[i] = ContactChannel(source: ch.source, handle: ch.handle, isPrimary: false);
        }
      }
    }

    final isPrimary = makePrimary || c.channels.isEmpty;
    c.channels.add(ContactChannel(source: source, handle: normalizedHandle, isPrimary: isPrimary));
    _reindexContact(c);
    _persist(c);
    _bump();
  }

bool _looksPlaceholderName(String s) {
    final t = s.trim();
    if (t.isEmpty) return true;
    if (t.startsWith('Group with Telegram')) return true;
    if (t.startsWith('Telegram ')) return true;
    // If it's just digits (e.g., "143216999") it's likely a placeholder id.
    if (RegExp(r'^\d{6,}$').hasMatch(t)) return true;
    // RoomId-looking handles should not be shown as name.
    if (t.startsWith('!') && t.contains(':')) return true;
    return false;
  }

  /// Update display name if the current one looks like a placeholder.
  void improveDisplayName(String contactId, String newDisplayName) {
    final c = _byId[contactId];
    if (c == null) return;
    final dn = newDisplayName.trim();
    if (dn.isEmpty) return;

    if (_looksPlaceholderName(c.displayName) && dn != c.displayName) {
      c.displayName = dn;
      _reindexContact(c);
      _persist(c);
      _bump();
    }
  }
}
