import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqlite;

import 'matrix_ui_logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MatrixSessionInfo {
  bool get isLoggedIn => (userId != null && userId!.isNotEmpty);
  final String? userId;
  final String? deviceId;
  final Uri? homeserver;
  final bool loggedIn;

  const MatrixSessionInfo({
    required this.userId,
    required this.deviceId,
    required this.homeserver,
    required this.loggedIn,
  });
}

class MatrixService {
  // Poll interval used by optional timers (older code paths expect `delay`).
  // Keep this getter for backwards compatibility.
  Duration get delay => const Duration(seconds: 2);

  /// Human-readable connection status for UI.
  final ValueNotifier<String> status = ValueNotifier<String>('');

  /// True when client is logged in (used by UI to switch Connect/Disconnect).
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  /// Bumps whenever rooms list or last events change (Inbox adapter listens to it).
  final ValueNotifier<int> roomsVersion = ValueNotifier<int>(0);


  MatrixService._internal();
  static final MatrixService instance = MatrixService._internal();

  static const _storage = FlutterSecureStorage();

  Client? _client;
  MatrixSdkDatabase? _db;
  StreamSubscription? _syncSub;
  DateTime? _lastSyncAt;

  /// Expected Telegram puppet MXID for the next DM that the bridge creates.
  /// Used to auto-open the correct room after "pm <phone>".
  String? _expectedDirectMxid;

  String? get expectedDirectMxid => _expectedDirectMxid;

  // Cache management-room ids for bridge bots to avoid creating multiple DMs.
  final Map<String, String> _botDmRoomIdByMxid = <String, String>{};

  Uri? _homeserver;

  /// True when мы уверены, что клиент реально может ходить на сервер (sync/ping OK).
  final ValueNotifier<bool> online = ValueNotifier<bool>(false);

  void _setStatus(String s) {
    status.value = s;
    _log(s);
  }

  void _log(String m, {Object? err, StackTrace? st}) {
    final b = StringBuffer('[MatrixService] $m');
    if (err != null) b.write(' | err=$err');
    if (st != null) b.write('\n$st');
    MatrixUiLogger.instance.log(b.toString());
  }

  Client? get client => _client;
  Uri? get homeserver => _homeserver;

  

Future<Map<String, String?>> loadSavedAuth() async {
  return {
    'hs': await _storage.read(key: 'matrix_hs'),
    'token': await _storage.read(key: 'matrix_token'),
    'user': await _storage.read(key: 'matrix_user'),
    'pass': await _storage.read(key: 'matrix_pass'),
  };
}

Future<MatrixSessionInfo?> autoConnectFromSaved({bool force = false}) async {
    if (force) {
      await _resetClientForReconnect();
    }

    final hs = await _storage.read(key: 'matrix_hs');
    final user = await _storage.read(key: 'matrix_user');
    final pass = await _storage.read(key: 'matrix_pass');
    final token = await _storage.read(key: 'matrix_token');

    final hsOk = hs != null && hs.trim().isNotEmpty;
    final userOk = user != null && user.trim().isNotEmpty;
    final passOk = pass != null && pass.isNotEmpty;
    final tokenOk = token != null && token.trim().isNotEmpty;

    if (!hsOk) {
      _log('autoConnectFromSaved: nothing saved');
      return null;
    }

    // Prefer password auto-login if available (user asked explicitly).
    if (userOk && passOk) {
      _log('autoConnectFromSaved: found saved username+password, trying password login...');
      return connectWithPassword(
        homeserver: hs!.trim(),
        username: user!.trim(),
        password: pass!,
        force: force,
      );
    }

    if (tokenOk) {
      _log('autoConnectFromSaved: found saved token, trying token login...');
      return connectWithAccessToken(
        homeserver: hs!.trim(),
        accessToken: token!.trim(),
        force: force,
      );
    }

    _log('autoConnectFromSaved: nothing saved');
    return null;
  }

  Future<void> _resetClientForReconnect() async {
    try {
      _syncSub?.cancel();
    } catch (_) {}
    _syncSub = null;
    online.value = false;
    connected.value = false;

    // Recreate client from scratch (without logging out, so we can re-login using saved creds).
    _client = null;
    _db = null;
  }


  Future<void> _ensureClient() async {
    if (_client != null) return;

    final dir = await getApplicationSupportDirectory();
    final dbPath = '${dir.path}/matrix_sdk.sqlite';
    _log('Opening MatrixSdkDatabase at $dbPath');

    final sqliteDb = await sqlite.openDatabase(dbPath);
    _db = await MatrixSdkDatabase.init('demo_app_matrix', database: sqliteDb);

    _client = Client(
      'demo_app',
      database: _db!,
    );

    await _client!.init();
    _log('Client.init() OK');

    // Restore homeserver from SDK if possible (important when SDK восстановил сессию из БД).
    try {
      _homeserver ??= _client!.homeserver;
    } catch (_) {}

    // Keep connected notifier in sync with SDK.
    connected.value = _client!.isLogged();
    _client!.onLoginStateChanged.stream.listen((_) {
      connected.value = _client!.isLogged();
    });
  }

  Uri _parseHomeserver(String raw) {
    final s = raw.trim();
    // Accept:
    // - http://host:port
    // - https://host
    // - host (domain) -> assume https
    // - host:port -> assume http (common for local/test)
    final uri = Uri.tryParse(s);
    if (uri != null && uri.hasScheme) return uri;

    if (s.contains(':')) {
      return Uri.parse('http://$s');
    }
    return Uri.https(s, '');
  }

  Future<MatrixSessionInfo> connectWithAccessToken({
    bool force = false,
    required String homeserver,
    required String accessToken,
  }) async {
    await _ensureClient();

    // Avoid "already logged in" precondition errors.
    final already = _client;
    if (!force && already != null) {
      try {
        if (!force && already.isLogged()) {
          connected.value = true;
          _setStatus('connect: already logged');
          _log('connectWithAccessToken: already logged-in, reusing session');
          // Still ensure sync is running.
          await _startSync();
          return _sessionInfo();
        }
      } catch (_) {
        // ignore
      }
    }

    _homeserver = _parseHomeserver(homeserver);
    final client = _client!;
    _setStatus('connect: token → check homeserver');
    _log('connectWithAccessToken: homeserver=$_homeserver');

    try {
      await client.checkHomeserver(_homeserver!).timeout(const Duration(seconds: 5));
    } on TimeoutException catch (_) {
      _setStatus('connect: checkHomeserver timeout (ignored)');
    } catch (e) {
      _setStatus('connect: checkHomeserver failed (ignored): $e');
    }
    _setStatus('connect: token → login');

    // Token login (works even if we already have a token in DB, but safest is explicit)
    await client.login(
      LoginType.mLoginToken,
      token: accessToken,
    ).timeout(const Duration(seconds: 20));

    await _storage.write(key: 'matrix_hs', value: homeserver.trim());
    await _storage.write(key: 'matrix_token', value: accessToken.trim());

    connected.value = true;
    _log('login(token) OK user=${client.userID} device=${client.deviceID}');
    await _startSync();
    return _sessionInfo();
  }

  Future<MatrixSessionInfo> connectWithPassword({
    bool force = false,
    required String homeserver,
    required String username,
    required String password,
  }) async {
    await _ensureClient();

    // Avoid "already logged in" precondition errors.
    final already = _client;
    if (!force && already != null) {
      try {
        if (!force && already.isLogged()) {
          connected.value = true;
          _setStatus('connect: already logged');
          _log('connectWithPassword: already logged-in, reusing session');
          await _startSync();
          return _sessionInfo();
        }
      } catch (_) {
        // ignore
      }
    }

    _homeserver = _parseHomeserver(homeserver);
    final client = _client!;
    _setStatus('connect: password → check homeserver');
    _log('connectWithPassword: homeserver=$_homeserver user=$username');

    try {
      await client.checkHomeserver(_homeserver!).timeout(const Duration(seconds: 5));
    } on TimeoutException catch (_) {
      _setStatus('connect: checkHomeserver timeout (ignored)');
    } catch (e) {
      _setStatus('connect: checkHomeserver failed (ignored): $e');
    }
    _setStatus('connect: token → login');

    await client.login(
      LoginType.mLoginPassword,
      password: password,
      identifier: AuthenticationUserIdentifier(user: username),
      // Some older servers still like having `user` duplicated. Harmless to set.
      user: username,
    ).timeout(const Duration(seconds: 20));

    await _storage.write(key: 'matrix_user', value: username.trim());
    await _storage.write(key: 'matrix_pass', value: password);

    final token = client.accessToken;
    if (token != null && token.isNotEmpty) {
      await _storage.write(key: 'matrix_hs', value: homeserver.trim());
      await _storage.write(key: 'matrix_token', value: token);
      _log('Saved access_token from password login.');
    } else {
      _log('WARNING: accessToken is null after password login.');
    }

    _setStatus('connect: login OK');
    connected.value = true;
    _log('login(password) OK user=${client.userID} device=${client.deviceID}');
    await _startSync();
    return _sessionInfo();
  }

  Future<void> _startSync() async {
    final client = _client;
    if (client == null) return;

    // Ensure we get initial data now.
    _setStatus('sync: oneShotSync…');
    try {
      await client.oneShotSync(timeout: const Duration(seconds: 10));
      online.value = true;
    } on TimeoutException catch (_) {
      _setStatus('sync: oneShotSync timeout (continue)');
    } catch (e) {
      _setStatus('sync: oneShotSync error (continue): $e');
      // If sync fails due to network/server, mark offline.
      online.value = false;
    }
    _setStatus('sync: rooms=${client.rooms.length}');
    roomsVersion.value++;
// Auto-accept invites (handy for bridging portals).
    try {
      await _autoJoinInvites(reason: 'after oneShotSync');
    } catch (e) {
      _log('autoJoinInvites error: $e');
    }

    // Start background sync.
    client.backgroundSync = true;
    _setStatus('sync: backgroundSync enabled');

    // Keep a subscription only for logging. UI can listen to client.onSync.stream.
    _syncSub?.cancel();
    _syncSub = client.onSync.stream.listen(
      (u) {
        if (u.hasRoomUpdate) {
          _log('onSync: room update (rooms=${client.rooms.length})');
          roomsVersion.value++;
// If we get invited while app is running, auto-join.
          _autoJoinInvites(reason: 'onSync').catchError((_) {});
        }
        // Any successful sync tick means we're online.
        online.value = true;
        _lastSyncAt = DateTime.now();
      },
      onError: (e, st) {
        _log('onSync error: $e');
        online.value = false;
      },
    );
  }

  bool _recentlyOnline({Duration within = const Duration(seconds: 30)}) {
    final t = _lastSyncAt;
    if (t == null) return false;
    return DateTime.now().difference(t) <= within;
  }

  /// Best-effort check that the client can talk to the homeserver right now.
  /// Returns true if a quick call succeeds, otherwise false.
  Future<bool> ensureOnline({Duration timeout = const Duration(seconds: 6), bool requireFreshSync = false}) async {
    final c = _client;
    if (c == null || !c.isLogged()) {
      online.value = false;
      return false;
    }
    // If we have a recent sync tick, don't do an extra oneShotSync.
    // oneShotSync may get cancelled on some Android devices when the client is already syncing.
    if (online.value == true && _recentlyOnline()) {
      return true;
    }
    // matrix >= 6.0.0 doesn't expose whoAmI(); use a short oneShotSync as a ping.
    try {
      await c.oneShotSync(timeout: timeout);
      online.value = true;
      _lastSyncAt = DateTime.now();
      return true;
    } catch (e) {
      _log('ensureOnline: oneShotSync failed: $e');
      // If we're logged in and already have rooms, treat this as "possibly online".
      // We'll still try bridge commands – worst case they time out and we show a clear error.
      if (c.isLogged() && c.rooms.isNotEmpty) {
        online.value = true;
        return true;
      }
      online.value = false;
      return false;
    }
  }

  
Future<int> _autoJoinInvites({String reason = ''}) async {
  final client = _client;
  if (client == null) return 0;
  int joined = 0;
  // The SDK represents rooms as Room objects. Invites usually appear as rooms with membership=invite.
  for (final r in client.rooms) {
    try {
      final dynRoom = r as dynamic;
      final mem = dynRoom.membership;
      final memStr = mem?.toString().toLowerCase() ?? '';
      if (memStr.contains('invite')) {
        final roomId = dynRoom.id ?? dynRoom.roomId ?? dynRoom.roomID;
        if (roomId is String && roomId.isNotEmpty) {
          // Try the most common APIs (SDK changes across versions).
          try {
            await (client as dynamic).joinRoom(roomId);
          } catch (_) {
            try {
              await (dynRoom as dynamic).join();
            } catch (_) {
              // ignore
            }
          }
          joined += 1;
          _log('autoJoinInvites: joined $roomId ${reason.isNotEmpty ? "($reason)" : ""}');
        }
      }
    } catch (_) {
      // ignore per-room
    }
  }
  if (joined > 0) _log('autoJoinInvites: joinedCount=$joined');
  return joined;
}

MatrixSessionInfo _sessionInfo() {
    final c = _client;
    return MatrixSessionInfo(
      userId: c?.userID,
      deviceId: c?.deviceID,
      homeserver: _homeserver,
      loggedIn: c?.isLogged() ?? false,
    );
  }

  Future<MatrixSessionInfo> refreshOnce() async {
    final c = _client;
    if (c == null) return _sessionInfo();

    _log('refreshOnce: oneShotSync start');
    await c.oneShotSync(timeout: const Duration(seconds: 30));
    _log('refreshOnce: oneShotSync done rooms=${c.rooms.length}');
    return _sessionInfo();
  }

  Future<void> logout() async {
    _log('logout: start');
    try {
      await _client?.logout();
    } catch (e) {
      _log('logout: ignore error: $e');
    }
    try {
      await _storage.delete(key: 'matrix_token');
    } catch (_) {}
    _syncSub?.cancel();
    _syncSub = null;
    connected.value = false;
    _client = null;
    _db = null;
    _homeserver = null;
    _log('logout: done');
  }


void _upsertMatrixRoomsIntoInbox() {
  final c = _client;
  if (c == null || !c.isLogged()) return;
  final rooms = c.rooms;
  for (final r in rooms) {
    // Each Matrix room becomes a conversation in the main Inbox.
    // handle = roomId, displayName = room name
    try {
      final name = (r.displayname.isNotEmpty) ? r.displayname : r.id;
      
// ConversationStore call removed (MatrixService is isolated)

    } catch (_) {
      // ignore
    }
  }
}


// ===== Bridge helpers (mautrix-telegram / mautrix-whatsapp) =====

String _defaultBotMxid(String localpart) {
  // IMPORTANT:
  // If Synapse is accessed via an IP (or IP:port), hs.host will be that IP.
  // But MXID domains must match the server_name of the homeserver (here it's
  // tg.agatzub.ru). Otherwise the bot MXID becomes invalid and the app will
  // fail to find/create the management DM.
  if (localpart == 'telegrambot') {
    return '@telegrambot:tg.agatzub.ru';
  }

  final hs = _client?.homeserver;
  final host = hs?.host ?? '';
  if (host.isEmpty) {
    throw Exception('Matrix homeserver не задан');
  }
  return '@$localpart:$host';
}

Future<Room> _ensureBotDM(String botMxid) async {
  final client = _client;
  if (client == null) throw Exception('Matrix не инициализирован');

  // 0) Lead with cached room id (prevents creating many "Bridge bot" rooms).
  final cachedId = _botDmRoomIdByMxid[botMxid];
  if (cachedId != null) {
    final cachedRoom = client.getRoomById(cachedId);
    if (cachedRoom != null) return cachedRoom;
  }

  // 1) Пробуем найти уже существующий DM (если SDK пометил как direct)
  for (final r in client.rooms) {
    if (r.isDirectChat && r.directChatMatrixID == botMxid) {
      _botDmRoomIdByMxid[botMxid] = r.id;
      return r;
    }
  }

  // 1b) Фоллбек: некоторые SDK/серверы не выставляют isDirectChat/directChatMatrixID.
  // Тогда используем эвристику "Bridge bot" + участники (я + бот).
  for (final r in client.rooms) {
    if (r.membership != Membership.join) continue;
    // Быстрый фильтр по названию (чтобы не делать requestParticipants на все комнаты).
    final dn = (r.displayname).toString();
    if (dn != 'Bridge bot') continue;
    try {
      final users = await r.requestParticipants(
        const [Membership.join, Membership.invite],
        true,
        false,
      );
      final ids = users.map((u) => u.id).toSet();
      if (ids.contains(botMxid) && ids.contains(client.userID) && ids.length == 2) {
        _botDmRoomIdByMxid[botMxid] = r.id;
        return r;
      }
    } catch (_) {
      // ignore and continue
    }
  }

  // 2) Фоллбек: ищем комнату "я + бот" по участникам
  for (final r in client.rooms) {
    if (r.membership != Membership.join) continue;
    try {
      final users = await r.requestParticipants(
        const [Membership.join, Membership.invite],
        true,
        false,
      );
      final ids = users.map((u) => u.id).toSet();
      if (ids.contains(botMxid) && ids.contains(client.userID) && ids.length == 2) {
        _botDmRoomIdByMxid[botMxid] = r.id;
        return r;
      }
    } catch (_) {
      // ignore and continue
    }
  }

  // 3) Создаем новый DM с ботом
  final roomId = await client.createGroupChat(
    invite: [botMxid],
    preset: CreateRoomPreset.privateChat,
    waitForSync: true,
    groupName: 'Bridge bot',
    enableEncryption: false,
  );

  // Кэшируем сразу, даже если Room объект появится чуть позже.
  _botDmRoomIdByMxid[botMxid] = roomId;

  // Ждём появления комнаты в client.rooms
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(end)) {
    final room = client.getRoomById(roomId);
    if (room != null) return room;
    await Future.delayed(const Duration(milliseconds: 250));
  }

  throw Exception('Не удалось получить комнату управления мостом');
}

  /// Best-effort: find a room created by telegram bridge for a given phone.
  /// We match against room displayname/name/topic and normalize phone digits.
  Future<String?> waitTelegramPortalRoomByPhone(String phoneE164, {Duration timeout = const Duration(seconds: 12)}) async {
    final client = _client;
    if (client == null) return null;

    String norm(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');
    final wanted = norm(phoneE164);

    bool matches(Room r) {
      String d = '';
      try { d = (r.displayname ?? '').toString(); } catch (_) {}
      String n = '';
      try { n = ((r as dynamic).name ?? '').toString(); } catch (_) {}
      String t = '';
      try { t = ((r as dynamic).topic ?? '').toString(); } catch (_) {}
      final text = '$d $n $t';
      final m = RegExp(r'(\+?\d[\d\s\-()]{7,}\d)').firstMatch(text);
      if (m == null) return false;
      final got = norm(m.group(1)!);
      return got == wanted || got.endsWith(wanted.replaceFirst('+', ''));
    }

    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      for (final r in client.rooms) {
        if (r.id.startsWith('!') && r.membership == Membership.join) {
          if (matches(r)) return r.id;
        }
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }
    return null;
  }

  /// High-level helper: ask bridge to open a PM by phone and then wait for the portal room to appear.
  
Future<void> _sendMgmtWithRetry({
  required String mgmtRoomId,
  required String text,
  int attempts = 3,
  Duration baseDelay = const Duration(milliseconds: 600),
}) async {
  Object? lastErr;
  StackTrace? lastSt;
  for (var i = 0; i < attempts; i++) {
    try {
      await _client!.getRoomById(mgmtRoomId)!.sendTextEvent(text);
      return;
    } catch (e, st) {
      lastErr = e;
      lastSt = st;
      _log('mgmt send failed (attempt ${i + 1}/$attempts): $e', st: st);
      if (i < attempts - 1) {
        final d = Duration(milliseconds: baseDelay.inMilliseconds * (1 << i));
        await Future<void>.delayed(d);
      }
    }
  }
  // After retries
  _log('mgmt send giving up: $lastErr', st: lastSt);
  throw lastErr ?? Exception('mgmt send failed');
}

Future<String?> createTelegramPortalByPhone(
    String phoneE164, {
    String? displayName,
    void Function(String stage)? onProgress,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final client = _client;
    if (client == null || !client.isLogged()) return null;

    // Если Matrix не онлайн, попробуем форс-переподключение из сохраненных данных.
    var isOk = await ensureOnline();
    if (!isOk) {
      await autoConnectFromSaved(force: true);
      isOk = await ensureOnline(timeout: const Duration(seconds: 10));
    }
    if (!isOk) return null;

    try {
      final botMxid = _defaultBotMxid('telegrambot');
      onProgress?.call('Открываю management-room…');
      final dm = await _ensureBotDM(botMxid);

      // Snapshot текущих комнат: после `pm` мост обычно делает invite в новую portal-room.
      final beforeRooms = client.rooms.map((r) => r.id).toSet();

      // ВАЖНО: это DM/management room с ботом (@telegrambot:...)
      // В management room команды отправляются БЕЗ префикса (!tg не нужен).
      // 1) add-contact (best-effort)
      // 2) sync contacts
      // 3) pm
      final name = (displayName == null || displayName.trim().isEmpty) ? phoneE164 : displayName.trim();
      final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      final first = parts.isNotEmpty ? parts.first : phoneE164;
      final last = parts.length >= 2 ? parts.sublist(1).join(' ') : '-';

      onProgress?.call('Добавляю контакт в Telegram…');
      await dm.sendTextEvent('add-contact $phoneE164 $first $last');
      await Future.delayed(const Duration(milliseconds: 800));

      final importedTgId = await _waitForBotRegex(
        dm: dm,
        pattern: RegExp(r'\bID\s+(\d{4,})\b'),
        timeout: const Duration(seconds: 10),
      );

      onProgress?.call('Синхронизирую контакты…');
      await dm.sendTextEvent('sync contacts');
      await Future.delayed(const Duration(milliseconds: 1200));

      onProgress?.call('Создаю чат…');
      await dm.sendTextEvent('pm $phoneE164');
      onProgress?.call('Ожидаю комнату…');

      final expectedPuppetMxid = importedTgId == null
          ? null
          : '@telegram_${importedTgId}:${_client!.homeserver!.host}';

      // Remember the expected puppet for auto-detection in _waitNewJoinedRoom.
      _expectedDirectMxid = expectedPuppetMxid;

      // If the portal already exists (or got created very fast), it may already be present.
      if (expectedPuppetMxid != null) {
        final existing = _findDirectRoomWithMxid(expectedPuppetMxid);
        if (existing != null) {
          _expectedDirectMxid = null;
          return existing;
        }
      }

      // Важный момент: портал-рум может называться как угодно (имя контакта),
      // поэтому искать по номеру в displayname ненадёжно.
      // Мост почти всегда отвечает в DM текстом с room id вида !abc:server.
      final roomId = await _waitPortalRoomIdFromBot(dm);
      if (roomId == null) {
        // 1) Фоллбек: ждём появление новой комнаты (invite/join)
        final created = await _waitNewJoinedRoom(beforeRooms, timeout: timeout);
        if (created != null) {
          _expectedDirectMxid = null;
          return created;
        }

        // 2) Старый фоллбек на эвристику по номеру.
        return await waitTelegramPortalRoomByPhone(phoneE164);
      }

      // Авто-джоин (на случай если invite ещё не принят).
      try {
        final r = client.getRoomById(roomId);
        if (r != null && r.membership != Membership.join) {
          await r.join();
        }
      } catch (_) {}

      _expectedDirectMxid = null;
      return roomId;
    } catch (e) {
      _log('createTelegramPortalByPhone error: $e');
      return null;
    }
  }

  /// Wait until a *new* joined room appears compared to [before].
  /// This is useful for bridges that invite you to a new portal room after `pm`.
  Future<String?> _waitNewJoinedRoom(Set<String> before, {Duration timeout = const Duration(seconds: 15)}) async {
    final client = _client;
    if (client == null) return null;

    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      try {
        // Force a sync tick so newly created portal rooms become visible even
        // if the background sync loop is currently stopped/suspended.
        await refreshOnce();

        // Accept invites eagerly.
        await _autoJoinInvites(reason: 'waitNewJoinedRoom');
      } catch (_) {}

			// `expectedDirectMxid` is a getter returning `String?`.
			// Capture it into a local variable so nullability is narrowed.
			final mxid = expectedDirectMxid;
			if (mxid != null) {
			  final found = _findDirectRoomWithMxid(mxid);
			  if (found != null) return found;
			}

      String? best;
      int bestScore = -1;
      for (final r in client.rooms) {
        if (before.contains(r.id)) continue;
        if (r.membership != Membership.join) continue;

        // Filter out obvious management rooms.
        final dn = (r.displayname ?? '').toString().toLowerCase();
        if (dn.contains('bridge bot') || dn.contains('telegrambot') || dn.contains('whatsappbot')) continue;

        // Score: prefer rooms with some name/message.
        int score = 0;
        if (dn.isNotEmpty) score += 2;
        try {
          final last = (r as dynamic).lastEvent ?? (r as dynamic).lastEventId;
          if (last != null) score += 1;
        } catch (_) {}
        if (score > bestScore) {
          bestScore = score;
          best = r.id;
        }
      }

      if (best != null) return best;
      await Future.delayed(const Duration(milliseconds: 600));
    }
    return null;
  }

  /// Waits for a management-bot reply that contains a portal room id.
  /// Typical reply includes something like "Created room !xxxx:hs".
  Future<String?> _waitPortalRoomIdFromBot(Room dm, {Duration timeout = const Duration(seconds: 12)}) async {
    try {
      final completer = Completer<String?>();

      Timeline? timeline;
      timeline = await dm.getTimeline(
        onUpdate: () {
          // scan whole list (cheap, small)
          final rid = _extractRoomIdFromTimeline(timeline);
          if (rid != null && !completer.isCompleted) completer.complete(rid);
        },
        onInsert: (i) {
          final rid = _extractRoomIdFromTimeline(timeline);
          if (rid != null && !completer.isCompleted) completer.complete(rid);
        },
        onChange: (i) {
          final rid = _extractRoomIdFromTimeline(timeline);
          if (rid != null && !completer.isCompleted) completer.complete(rid);
        },
        onRemove: (i) {},
      );

      // Also scan immediately.
      final immediate = _extractRoomIdFromTimeline(timeline);
      if (immediate != null) return immediate;

      // Wait until timeout.
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (e) {
      _log('_waitPortalRoomIdFromBot failed: $e');
      return null;
    }
  }

  String? _extractRoomIdFromTimeline(Timeline? timeline) {
    if (timeline == null) return null;
    // Scan last ~30 events for a room id token.
    final events = timeline.events;
    final start = events.length > 30 ? events.length - 30 : 0;
    for (int i = events.length - 1; i >= start; i--) {
      try {
        final ev = events[i];
        final body = ev.getDisplayEvent(timeline).body.toString();
        final m = RegExp(r'(![A-Za-z0-9]+:[A-Za-z0-9.:-]+)').firstMatch(body);
        if (m != null) return m.group(1);
      } catch (_) {
        // ignore
      }
    }
    return null;
  }

/// Старт приватного чата в Telegram через mautrix-telegram, командой `pm <phone>`
Future<bool> startTelegramPmByPhone(String phoneE164, {String? displayName}) async {
  final client = _client;
  if (client == null || !(connected.value)) return false;
  try {
    final botMxid = _defaultBotMxid('telegrambot');
    final room = await _ensureBotDM(botMxid);

    // Важно:
    // - `pm <phone>` работает только если номер есть в Telegram-контактах аккаунта моста.
    // - Начиная с mautrix-telegram v0.15.0 есть команда `add-contact`, которая добавляет номер в контакты Telegram.
    // Поэтому делаем:
    //   1) add-contact (если команда не поддерживается — бот ответит ошибкой, но мы не падаем)
    //   2) sync contacts (на случай, если мост кэширует список)
    //   3) pm <phone>
    final name = (displayName == null || displayName.trim().isEmpty) ? phoneE164 : displayName.trim();

    // Разбиваем имя на first/last, чтобы команда была более совместимой.
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final first = parts.isNotEmpty ? parts.first : phoneE164;
    final last = parts.length >= 2 ? parts.sublist(1).join(' ') : '-';

    await room.sendTextEvent('add-contact $phoneE164 $first $last');
    await _sendMgmtWithRetry(mgmtRoomId: room.id, text: 'sync contacts');
    await room.sendTextEvent('pm $phoneE164');
    return true;
  } catch (_) {
    return false;
  }
}


/// Старт приватного чата в WhatsApp через mautrix-whatsapp, командой `pm <phone>`
Future<bool> startWhatsAppPmByPhone(String phoneE164) async {
  final client = _client;
  if (client == null || !(connected.value)) return false;
  try {
    final botMxid = _defaultBotMxid('whatsappbot');
    final room = await _ensureBotDM(botMxid);
    await room.sendTextEvent('pm $phoneE164');
    return true;
  } catch (_) {
    return false;
  }
}

  String? _findDirectRoomWithMxid(String mxid) {
    final client = _client;
    if (client == null) return null;

    for (final room in client.rooms) {
      try {
        final isDirect = room.isDirectChat == true;
        final joined = room.membership == Membership.join;
        if (isDirect && joined && room.directChatMatrixID == mxid) {
          return room.id;
        }
      } catch (_) {
        // ignore
      }
    }
    return null;
  }

  Future<String?> _waitForBotRegex({
    required Room dm,
    required RegExp pattern,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      // In matrix SDK 6.x Room.timeline is gone; use getTimeline().
      final tl = await dm.getTimeline(limit: 50);
      final events = tl.events;
      for (final e in events.reversed) {
        try {
          final body = e.content.tryGet<String>('body');
          if (body == null) continue;
          final m = pattern.firstMatch(body);
          if (m != null) {
            return m.group(1);
          }
        } catch (_) {
          // ignore
        }
      }

      await Future.delayed(const Duration(milliseconds: 350));
    }

    return null;
  }

}
