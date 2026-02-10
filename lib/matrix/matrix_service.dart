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

  Uri? _homeserver;

  void _setStatus(String s) {
    status.value = s;
    _log(s);
  }

  void _log(String m) => MatrixUiLogger.instance.log('[MatrixService] $m');

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

Future<MatrixSessionInfo?> autoConnectFromSaved() async {
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
      );
    }

    if (tokenOk) {
      _log('autoConnectFromSaved: found saved token, trying token login...');
      return connectWithAccessToken(homeserver: hs!.trim(), accessToken: token!.trim());
    }

    _log('autoConnectFromSaved: nothing saved');
    return null;
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
    required String homeserver,
    required String accessToken,
  }) async {
    await _ensureClient();

    // Avoid "already logged in" precondition errors.
    final already = _client;
    if (already != null) {
      try {
        if (already.isLogged()) {
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
    required String homeserver,
    required String username,
    required String password,
  }) async {
    await _ensureClient();

    // Avoid "already logged in" precondition errors.
    final already = _client;
    if (already != null) {
      try {
        if (already.isLogged()) {
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
    } on TimeoutException catch (_) {
      _setStatus('sync: oneShotSync timeout (continue)');
    } catch (e) {
      _setStatus('sync: oneShotSync error (continue): $e');
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
      },
      onError: (e, st) => _log('onSync error: $e'),
    );
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

}
