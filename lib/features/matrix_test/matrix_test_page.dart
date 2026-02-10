import 'package:flutter/material.dart';

import 'matrix_room_page.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../../matrix/matrix_service.dart';
import '../../matrix/matrix_ui_logger.dart';

class MatrixTestPage extends StatefulWidget {
  const MatrixTestPage({super.key});

  @override
  State<MatrixTestPage> createState() => _MatrixTestPageState();
}

class _MatrixTestPageState extends State<MatrixTestPage> {
  bool get connected => MatrixService.instance.client?.isLogged() ?? false;

  final _homeserverCtrl =
      TextEditingController(text: 'http://155.212.145.31:8008');

  // Token mode
  final _tokenCtrl = TextEditingController();

  // Password mode
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _usePassword = true;

  bool _loading = false;
  String? _error;

  MatrixSessionInfo? _session;

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      try {
        final saved = await MatrixService.instance.loadSavedAuth();
        if (!mounted) return;
        setState(() {
          final hs = (saved['hs'] ?? '').trim();
          _homeserverCtrl.text = (hs.isEmpty || hs.contains('tg.agatzub.ru'))
              ? 'http://155.212.145.31:8008'
              : hs;
          _tokenCtrl.text = (saved['token'] ?? '').trim();
          _userCtrl.text = (saved['user'] ?? '').trim();
          _passCtrl.text = (saved['pass'] ?? '');
        });

        // try auto-connect (if token saved)
        final info = await MatrixService.instance.autoConnectFromSaved();
        if (!mounted || info == null) return;
        setState(() => _session = info);
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      }
    });
  }

  @override
  void dispose() {
    _homeserverCtrl.dispose();
    _tokenCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final hs = _homeserverCtrl.text.trim();
      if (hs.isEmpty) throw Exception('Homeserver пустой');

      MatrixSessionInfo info;
      if (_usePassword) {
        final u = _userCtrl.text.trim();
        final p = _passCtrl.text;
        if (u.isEmpty) throw Exception('Не введён username');
        if (p.isEmpty) throw Exception('Не введён password');
        info = await MatrixService.instance.connectWithPassword(
          homeserver: hs,
          username: u,
          password: p,
        );
      } else {
        final t = _tokenCtrl.text.trim();
        if (t.isEmpty) throw Exception('Не введён access token');
        info = await MatrixService.instance.connectWithAccessToken(
          homeserver: hs,
          accessToken: t,
        );
      }

      if (!mounted) return;
      setState(() => _session = info);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _syncOnce() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await MatrixService.instance.refreshOnce();
      if (!mounted) return;
      setState(() => _session = info);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await MatrixService.instance.logout();
      if (!mounted) return;
      setState(() => _session = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _copyLogs() async {
    final txt = MatrixUiLogger.instance.text;
    await Clipboard.setData(ClipboardData(text: txt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Логи скопированы')),
    );
  }

  Widget _statusCard() {
    final s = _session;
    final c = MatrixService.instance.client;
    final logged = c?.isLogged() ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${logged ? "LOGGED" : "NOT LOGGED"}'),
            const SizedBox(height: 6),
            Text('Homeserver: ${MatrixService.instance.homeserver ?? "-"}'),
            Text('User: ${s?.userId ?? "-"}'),
            Text('Device: ${s?.deviceId ?? "-"}'),
            Text('Rooms: ${c?.rooms.length ?? 0}'),
          ],
        ),
      ),
    );
  }

  Widget _roomsCard() {
    final client = MatrixService.instance.client;
    if (client == null || !(client.isLogged())) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Комнаты появятся после успешного входа.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Комнаты',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: _loading ? null : _syncOnce,
                  child: const Text('Обновить'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: StreamBuilder(
                stream: client.onSync.stream,
                builder: (context, _) {
                  final rooms = client.rooms;
                  if (rooms.isEmpty) {
                    return const Text('Пока пусто. Нажми «Обновить».');
                  }
                  return ListView.separated(
                    itemCount: rooms.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = rooms[i];
                      return ListTile(
                        dense: true,
                        title: Text(r.displayname),
                        subtitle: Text(r.id),
                        onTap: () async {
                          try {
                            if (!mounted) return;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MatrixRoomPage(roomId: r.id),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Не удалось открыть: $e')),
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Логи',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: _copyLogs,
                  child: const Text('Скопировать'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: ValueListenableBuilder<String>(
                  valueListenable: MatrixUiLogger.instance.listenable,
                  builder: (context, text, _) {
                    return Text(
                      text.isEmpty ? 'Логи появятся тут…' : text,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _authCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _homeserverCtrl,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: 'Homeserver (http/https)',
                hintText: 'http://tg.agatzub.ru:8008',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _usePassword,
              onChanged: _loading ? null : (v) => setState(() => _usePassword = v),
              title: const Text('Вход по логину и паролю (иначе — по токену)'),
            ),
            const SizedBox(height: 8),
            if (_usePassword) ...[
              TextField(
                controller: _userCtrl,
                enabled: !_loading,
                decoration: const InputDecoration(labelText: 'Username (localpart)'),
                autocorrect: false,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                enabled: !_loading,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
            ] else ...[
              TextField(
                controller: _tokenCtrl,
                enabled: !_loading,
                decoration: const InputDecoration(labelText: 'Access Token'),
                autocorrect: false,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading ? null : (connected ? _logout : _connect),
                    child: Text(_loading ? '...' : (connected ? 'Отключить' : 'Подключить')),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                    onPressed: _loading ? null : (connected ? _logout : null),
                    child: const Text('Logout'),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = _session?.isLoggedIn ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matrix Test (SDK 6)'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _syncOnce,
            icon: const Icon(Icons.sync),
            tooltip: 'oneShotSync',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _authCard(),
            _statusCard(),
            _roomsCard(),
            _logsCard(),
          ],
        ),
      ),
    );
  }
}
