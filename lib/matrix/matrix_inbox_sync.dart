import 'dart:async';

import 'package:matrix/matrix.dart';

import '../shared/contact_store.dart';
import '../shared/conversation_store.dart';
import '../shared/message_source.dart';
import 'matrix_service.dart';
import 'matrix_ui_logger.dart';

/// Read-only adapter: mirrors Matrix rooms into ConversationStore so Inbox can render them.
/// MatrixService remains isolated and has no dependency on stores.

class _RoomIdentity {
  final String title;
  final String phoneOrUsername;
  const _RoomIdentity(this.title, this.phoneOrUsername);
}

class MatrixInboxSync {
  // Cache last seen lastEvent ids per room to avoid re-processing unchanged rooms.
  final Map<String, String> _lastEventIdByRoom = <String, String>{};

  MatrixInboxSync._();
  static final MatrixInboxSync instance = MatrixInboxSync._();

  Timer? _debounce;
  Timer? _periodic;

  void init() {
    // Listen for rooms updates.
    MatrixService.instance.roomsVersion.addListener(_onRoomsChanged);

    // Also react to connect/disconnect transitions.
    MatrixService.instance.connected.addListener(_onRoomsChanged);

    // Safety-net: some SDK flows may not bump roomsVersion (e.g. already-logged client).
    // Periodically attempt sync while app is running.
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(seconds: 15), (_) => _onRoomsChanged());

    // Attempt initial sync (in case connected already).
    _onRoomsChanged();
  }

  void dispose() {
    MatrixService.instance.roomsVersion.removeListener(_onRoomsChanged);
    MatrixService.instance.connected.removeListener(_onRoomsChanged);
    _debounce?.cancel();
    _debounce = null;
    _periodic?.cancel();
    _periodic = null;
  }


  DateTime _safeUpdatedAt(Room room) {
    final last = room.lastEvent;
    if (last != null) {
      try {
        final ts = (last as dynamic).originServerTs;
          if (ts == null) return DateTime.now();
          if (ts is int) {
            if (ts > 0) return DateTime.fromMillisecondsSinceEpoch(ts);
          } else if (ts is DateTime) {
            return ts;
          }
      } catch (_) {}
    }
    return DateTime.now();
  }

  void _log(String m) => MatrixUiLogger.instance.log('[MatrixInboxSync] $m');


String _stripTelegramSuffix(String s) {
  var t = s.trim();
  if (t.startsWith("'") && t.endsWith("'") && t.length > 1) {
    t = t.substring(1, t.length - 1).trim();
  }
  t = t.replaceAll('(Telegram)', '').trim();
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.startsWith('Group with ')) t = t.substring('Group with '.length).trim();
  if (t.startsWith('Telegram ')) t = t.substring('Telegram '.length).trim();
  return t.trim();
}

String _extractPhoneOrUsername(String text) {
  final t = text.trim();
  // Phone like +7 999 123-45-67 or +79001234567
  final phoneMatch = RegExp(r'(\+?\d[\d\s\-()]{7,}\d)').firstMatch(t);
  if (phoneMatch != null) {
    return phoneMatch.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  // Username like @name
  final userMatch = RegExp(r'@([a-zA-Z0-9_]{3,})').firstMatch(t);
  if (userMatch != null) return '@${userMatch.group(1)}';
  return '';
}

_RoomIdentity _computeIdentity(Room room) {
  String display = '';
  try { display = (room.displayname ?? '').toString(); } catch (_) {}
  String topic = '';
  try { topic = ((room as dynamic).topic ?? '').toString(); } catch (_) {}
  String name = '';
  try { name = ((room as dynamic).name ?? '').toString(); } catch (_) {}

  // Normalize/clean bridge prefixes and suffixes.
  final d0 = _stripTelegramSuffix(display);
  final n0 = _stripTelegramSuffix(name);
  final t0 = _stripTelegramSuffix(topic);

  // phone/username hint from any field
  final phone1 = _extractPhoneOrUsername(d0);
  final phone2 = _extractPhoneOrUsername(n0);
  final phone3 = phone2.isNotEmpty ? phone2 : (phone1.isNotEmpty ? phone1 : _extractPhoneOrUsername(t0));

  // Title preference:
  // 1) cleaned room name (mautrix often sets it to the Telegram display name)
  // 2) cleaned room displayname
  // 3) cleaned topic
  // 4) fallback: phone/username, else room id
  String title = '';

  String clean(String s) => _stripTelegramSuffix(s);

  final candidates = <String>[
    clean(n0),
    clean(d0),
    clean(t0),
  ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  for (final c in candidates) {
    if (c.startsWith('!')) continue; // raw room id
    if (c.toLowerCase().startsWith('group with telegram')) continue;
    if (c.toLowerCase().startsWith('telegram ')) continue;
    title = c;
    break;
  }

  // If title is just digits (Telegram internal id), prefer phone/username if present.
  if (RegExp(r'^\d{6,}$').hasMatch(title) && phone3.isNotEmpty) {
    title = '';
  }

  if (title.isEmpty && phone3.isNotEmpty) title = phone3;
  if (title.isEmpty) title = room.id;

  return _RoomIdentity(title, phone3);
}


// _preferredTitle removed; use _computeIdentity


  void _onRoomsChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _syncNow);
  }

  void _syncNow() {
    final svc = MatrixService.instance;
    final client = svc.client;
    if (client == null) return;

    bool isLogged = false;
    try {
      // Use SDK truth; connected notifier might lag right after token login.
      isLogged = client.isLogged();
    } catch (_) {
      // Fallback for SDK changes.
      isLogged = (client.accessToken ?? '').isNotEmpty;
    }
    if (!isLogged) {
      _log('skip: not logged');
      return;
    }

    final roomCount = client.rooms.length;
    _log('syncNow: rooms=$roomCount');

    // Migration: if older builds mirrored rooms as source=matrix, purge them from Inbox (in-memory).
    final removedOld = ConversationStore.instance.removeWhere(
      (c) => c.source == MessageSource.matrix && c.handle.startsWith('!'),
    );
    if (removedOld > 0) {
      _log('purged old matrix conversations: $removedOld');
    }

    // Hide bridge management rooms ("Bridge bot") from Inbox.
    // These rooms exist only to send commands to mautrix bots.
    final removedBot = ConversationStore.instance.removeWhere(
      (c) => c.source == MessageSource.telegram && c.lastMessage.contains('Matrix: Bridge bot'),
    );
    if (removedBot > 0) {
      _log('removed bridge bot conversations: $removedBot');
    }

    int updated = 0;

    for (final room in client.rooms) {
      try {
        final ident = _computeIdentity(room);
        final title = ident.title;
        final phoneOrUsername = ident.phoneOrUsername;

        // Skip bridge management DM rooms.
        if (title.trim().toLowerCase() == 'bridge bot') {
          continue;
        }

        // Best-effort last message preview.
        String preview = 'Matrix: $title';
        final last = room.lastEvent;
        final currentLastId = (last?.eventId ?? '').toString();
        final prevLastId = _lastEventIdByRoom[room.id] ?? '';
        if (currentLastId.isNotEmpty && currentLastId == prevLastId) {
          // Skip if unchanged and we already have this room in conversations.
          final exists = ConversationStore.instance.all.any((c) => c.source == MessageSource.telegram && c.handle == room.id);
          if (exists) {
            continue;
          }
        }
        if (last != null && last.type == EventTypes.Message) {
          final body = last.content['body'];
          if (body is String && body.trim().isNotEmpty) {
            preview = body.trim();
          }
        }

        final contact = ContactStore.instance.getOrCreateForIncoming(
          source: MessageSource.telegram,
          handle: room.id,
          displayName: title,
        );
        // If we discovered a better title later, upgrade the contact display name.
        ContactStore.instance.improveDisplayName(contact.id, title);
        if (phoneOrUsername.isNotEmpty) {
          ContactStore.instance.ensureChannel(contactId: contact.id, source: MessageSource.telegram, handle: phoneOrUsername, makePrimary: false);
        }


        ConversationStore.instance.upsertPreview(
          source: MessageSource.telegram,
          handle: room.id,
          contactId: contact.id,
          lastMessage: preview,
          updatedAt: _safeUpdatedAt(room),
        );

        _lastEventIdByRoom[room.id] = currentLastId;
        updated++;
      } catch (_) {
        // ignore errors per room
      }
    }

    _log('rooms mirrored into Inbox: $updated');
  }
}