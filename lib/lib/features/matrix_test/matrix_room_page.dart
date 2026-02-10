import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../matrix/matrix_service.dart';

class MatrixRoomPage extends StatefulWidget {
  final String roomId;
  const MatrixRoomPage({super.key, required this.roomId});

  @override
  State<MatrixRoomPage> createState() => _MatrixRoomPageState();
}

class _MatrixRoomPageState extends State<MatrixRoomPage> {
  final _msgCtrl = TextEditingController();

  Timeline? _timeline;
  bool _loading = true;
  String? _error;

  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  @override
  void initState() {
    super.initState();
    Future.microtask(_init);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = MatrixService.instance.client;
      if (client == null || !client.isLogged()) {
        throw Exception('Not logged in');
      }

      final room = client.rooms.firstWhere((r) => r.id == widget.roomId);

      // Auto-join if invited/left.
      if (room.membership != Membership.join) {
        await room.join();
      }

      // Create timeline. It keeps itself updated via callbacks.
      final timeline = await room.getTimeline(
        onUpdate: () {
          if (!mounted) return;
          setState(() {});
        },
        onInsert: (i) {
          // New event inserted -> animate
          _listKey.currentState?.insertItem(i);
          if (mounted) setState(() {});
        },
        onRemove: (i) {
          _listKey.currentState?.removeItem(
            i,
            (_, __) => const SizedBox.shrink(),
            duration: const Duration(milliseconds: 150),
          );
          if (mounted) setState(() {});
        },
        onChange: (i) {
          if (!mounted) return;
          setState(() {});
        },
      );

      setState(() {
        _timeline = timeline;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final t = _timeline;
    if (t == null) return;
    try {
      await t.requestHistory();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('History error: $e')),
      );
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    final client = MatrixService.instance.client;
    if (client == null || !client.isLogged()) return;

    final room = client.rooms.firstWhere((r) => r.id == widget.roomId);

    try {
      await room.sendTextEvent(text);
      _msgCtrl.clear();
      // New message should appear via timeline callbacks, but also refresh UI quickly.
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send error: $e')),
      );
    }
  }

  Widget _buildEventTile(Event ev) {
    // Skip relationship edits/reactions in this basic view.
    if (ev.relationshipEventId != null) return const SizedBox.shrink();

    final body = ev.getDisplayEvent(_timeline!).body;
    if (body.isEmpty) return const SizedBox.shrink();

    final sender = ev.sender.calcDisplayname();
    final ts = ev.originServerTs;

    return ListTile(
      dense: true,
      title: Text(body),
      subtitle: Text('$sender • ${ts.toLocal().toIso8601String()}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _timeline;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomId),
        actions: [
          IconButton(
            onPressed: _init,
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-init',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading)
            const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (t == null && !_loading && _error == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No timeline'),
            ),
          if (t != null) ...[
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _loadMore,
                child: const Text('Load more…'),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: AnimatedList(
                key: _listKey,
                reverse: true,
                initialItemCount: t.events.length,
                itemBuilder: (context, i, animation) {
                  final ev = t.events[i];
                  return SizeTransition(
                    sizeFactor: animation,
                    child: _buildEventTile(ev),
                  );
                },
              ),
            ),
          ] else
            const Expanded(child: SizedBox.shrink()),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _send,
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
