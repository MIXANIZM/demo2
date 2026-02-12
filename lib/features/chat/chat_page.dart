import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:demo_app/shared/widgets/full_emoji_picker.dart';
import 'package:demo_app/shared/app_settings_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' as mx;

import '../../providers/stores_providers.dart';

import '../../shared/db_service.dart';
import '../../shared/conversation_store.dart';
import '../../shared/conversation_models.dart';
import '../../shared/message_source.dart';
import '../../shared/contact_store.dart';
import '../../shared/contact_models.dart';
import '../contact/contact_page.dart';

import '../../matrix/matrix_service.dart';


const bool kEnableAutoReply = false; // DEBUG: easy to turn off later

class ChatPage extends ConsumerStatefulWidget {
  final String? conversationId;
  final String contactId;
  final MessageSource channelSource;
  final String channelHandle;

  const ChatPage({
    super.key,
    this.conversationId,
    required this.contactId,
    required this.channelSource,
    required this.channelHandle,
  });

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}



enum _ChatMenuAction {
  linkToContact,
}
class _ChatPageState extends ConsumerState<ChatPage> {
  // Local/optimistic map of MY reactions per message (supports Telegram Premium-style up to 3)
  final Map<String, List<String>> _myReactionsByMessageId = {};
  final Map<String, Map<String, String>> _myReactionEventIdsByTarget = {}; // targetEventId -> (emoji -> reactionEventId)


  // legacy compatibility getter
  bool get _isMatrixRoomAsTelegram => widget.channelSource == MessageSource.telegram && widget.channelHandle.startsWith('!');

  bool _isEmojiOpen = false;
  final FocusNode _focusNode = FocusNode();
  final Set<String> _mxPendingRedactions = <String>{};

  /// Optimistic reactions for Matrix rooms.
  ///
  /// Reactions can be successfully sent to Matrix/bridge, but the room timeline
  /// may update slightly later. Without this overlay, it can look like reactions
  /// "do not save" even though they were delivered.
  final Map<String, String> _mxPendingMyReactionByTarget = <String, String>{};

  /// Optimistic edits for Matrix rooms.
  ///
  /// Edits can be sent successfully but appear in the room timeline slightly
  /// later. We keep a temporary overlay per target event id.
  final Map<String, String> _mxPendingEditTextByTarget = <String, String>{};
  bool get _isTelegramChannel => widget.channelSource == MessageSource.telegram;
  bool get _isMatrixRoom => widget.channelHandle.startsWith('!');

  mx.Timeline? _mxTimeline;
  bool _mxLoadingHistory = false;
  bool _autoLoadingFullHistory = false;

  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  String _genId(int nowMs) => '${nowMs}_${_rng.nextInt(1<<32)}';

  final _rng = Random();

  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  bool _showEmojiKeyboard = false;
  double _lastViewInset = 0;

  static const double _kInputBarHeight = 56; // approx; used for list bottom padding
  static const double _kEmojiKeyboardHeight = 340;
  bool _hasText = false;
  final ScrollController _scroll = ScrollController();

  // Autoscroll behavior (WhatsApp-like):
  // - If user is at bottom -> autoscroll on new messages
  // - If user scrolled up -> keep position, show a "new messages" button
  static const double _bottomThresholdPx = 56; // how close to bottom counts as "at bottom"
  bool _isAtBottom = true;
  int _pendingNewMessages = 0;

  Color get _appBarColor => widget.channelSource.color;

  final GlobalKey _listKey = GlobalKey();
  final Map<String, GlobalKey> _dayHeaderKeys = {};
  String? _stickyDayLabel;
  bool _stickyVisible = false;

  final List<_UiMessage> _messages = [];
  String? _effectiveConversationId;
  bool _loading = true;

  Future<void> _openLinkToContactSheet() async {
    if (_effectiveConversationId == null) return;
    // Matrix room ids are typically like '!....:server'.
    // Note: even when the UI shows "Telegram", bridged chats still have Matrix room ids.
    final isRoomId = widget.channelHandle.startsWith('!');
    if (!isRoomId) return;

    final selectedContactId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return _ContactPickerSheet(
          initialSelectedId: widget.contactId,
        );
      },
    );

    if (!mounted) return;
    if (selectedContactId == null || selectedContactId.isEmpty) return;
    if (selectedContactId == widget.contactId) return;

    final convStore = ref.read(conversationStoreProvider);
    await convStore.linkConversationToContact(
      _effectiveConversationId!,
      selectedContactId,
      alsoUpsertChannel: true,
    );

    if (!mounted) return;

    // Re-open chat with the new bound contact.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          conversationId: _effectiveConversationId,
          contactId: selectedContactId,
          channelSource: widget.channelSource,
          channelHandle: widget.channelHandle,
        ),
      ),
    );
  }
  @override
  void initState() {
    super.initState();

    _controller.addListener(_syncHasText);
    _bootstrap();
    _scroll.addListener(_onScroll);
    _inputFocus.addListener(() {
      if (_inputFocus.hasFocus && mounted) {
        // If user taps into text input, hide the emoji panel.
        setState(() => _showEmojiKeyboard = false);
        _scrollToBottomSoon();
      }
    });
  }

  void _syncHasText() {
    final next = _controller.text.trim().isNotEmpty;
    if (next != _hasText && mounted) {
      setState(() => _hasText = next);
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scroll.hasClients) return;
      // Keep bottom visible when keyboard/panels change.
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _toggleEmojiKeyboard() {
    setState(() {
      _showEmojiKeyboard = !_showEmojiKeyboard;
    });
    if (_showEmojiKeyboard) {
      // Close system keyboard.
      FocusScope.of(context).unfocus();
    } else {
      // Re-open system keyboard.
      FocusScope.of(context).requestFocus(_inputFocus);
    }
    _scrollToBottomSoon();
  }

  void _insertEmojiToInput(String emoji) {
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    final newOffset = start + emoji.length;
    _controller.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
    _syncHasText();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scroll.removeListener(_onScroll);
    _controller.removeListener(_syncHasText);
    _controller.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final listCtx = _listKey.currentContext;
    if (listCtx == null) return;
    final listObj = listCtx.findRenderObject();
    if (listObj is! RenderBox) return;

    String? bestAbove;
    double bestAboveDy = -1e9;
    String? bestBelow;
    double bestBelowDy = 1e9;

    for (final entry in _dayHeaderKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final obj = ctx.findRenderObject();
      if (obj is! RenderBox || !obj.attached) continue;

      final dy = obj.localToGlobal(Offset.zero, ancestor: listObj).dy;

      if (dy <= 0 && dy > bestAboveDy) {
        bestAboveDy = dy;
        bestAbove = entry.key;
      } else if (dy > 0 && dy < bestBelowDy) {
        bestBelowDy = dy;
        bestBelow = entry.key;
      }
    }

    final current = bestAbove ?? bestBelow;
    final shouldShow = _scroll.hasClients && _scroll.offset > 0 && current != null;

    // Track whether the user is at (or very near) the bottom.
    if (_scroll.hasClients) {
      final max = _scroll.position.maxScrollExtent;
      final atBottomNow = (max - _scroll.offset) <= _bottomThresholdPx;
      if (atBottomNow != _isAtBottom) {
        setState(() {
          _isAtBottom = atBottomNow;
          if (_isAtBottom) {
            _pendingNewMessages = 0;
          }
        });
      } else if (_isAtBottom && _pendingNewMessages != 0) {
        // Safety: if user is at bottom, there shouldn't be pending messages.
        setState(() => _pendingNewMessages = 0);
      }
    }

    if (_stickyDayLabel != current || _stickyVisible != shouldShow) {
      setState(() {
        _stickyDayLabel = current;
        _stickyVisible = shouldShow;
      });
    }
  }

  Future<void> _bootstrap() async {
    await DbService.instance.init();

    final convId = widget.conversationId;
    if (convId != null) {
      _effectiveConversationId = convId;
    } else {
      final conv = ConversationStore.instance.ensureConversation(
        source: widget.channelSource,
        handle: widget.channelHandle,
        contactId: widget.contactId,
      );
      _effectiveConversationId = conv.id;
    }

    // При заходе в чат считаем диалог прочитанным
    final cid = _effectiveConversationId;
    if (cid != null) {
      ConversationStore.instance.markAsRead(cid);
    }

    // Matrix rooms bridged as Telegram: use Matrix timeline instead of local DB.
    if (_isMatrixRoom) {
      await _bootstrapMatrixTimeline();
      return;
    }

    final id = _effectiveConversationId;
    if (id != null) {
      final stored = await DbService.instance.loadMessages(
        contactId: widget.contactId,
        conversationId: id,
      );
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(
            stored.map(
              (m) => _UiMessage(
                id: m.id,
                text: m.text,
                isOutgoing: m.isOutgoing,
                createdAtMs: m.createdAtMs,
                reactions: _myReactionsByMessageId[m.id] ?? (m.myReaction != null ? [m.myReaction!] : []),
                editedAtMs: m.editedAtMs,
              ),
            ),
          );
        _loading = false;
        _isAtBottom = true;
        _pendingNewMessages = 0;
      });
      _scrollToBottom();
    } else {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _bootstrapMatrixTimeline() async {
    try {
      final client = MatrixService.instance.client;
      if (client == null || !client.isLogged()) {
        // Try auto-connect (non-blocking) and re-check quickly.
        await MatrixService.instance.autoConnectFromSaved();
      }

      final c2 = MatrixService.instance.client;
      if (c2 == null || !c2.isLogged()) {
        throw Exception('Matrix: not logged in');
      }

      final roomId = widget.channelHandle;
      final room = c2.rooms.firstWhere((r) => r.id == roomId);

      if (room.membership != mx.Membership.join) {
        await room.join();
      }

      final timeline = await room.getTimeline(
        onUpdate: () {
          if (!mounted) return;
          _syncUiFromMatrixTimeline();
        },
        onInsert: (_) {
          if (!mounted) return;
          _syncUiFromMatrixTimeline(newMessageLikely: true);
        },
        onRemove: (_) {
          if (!mounted) return;
          _syncUiFromMatrixTimeline();
        },
        onChange: (_) {
          if (!mounted) return;
          _syncUiFromMatrixTimeline();
        },
      );

      _mxTimeline = timeline;
      _syncUiFromMatrixTimeline();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isAtBottom = true;
        _pendingNewMessages = 0;
      });
      _scrollToBottom();

      // По умолчанию история подгружается по кнопке "Загрузить ещё".
      // Если в настройках включили автозагрузку — докачиваем историю до конца.
      unawaited(_autoLoadFullHistoryIfEnabled());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..add(
            _UiMessage(
              id: 'matrix_error',
              text: 'Matrix error: $e',
              isOutgoing: false,
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        _loading = false;
      });
    }
  }

  int _mxEventTsToMs(dynamic ts) {
    if (ts is DateTime) return ts.millisecondsSinceEpoch;
    if (ts is int) return ts;
    return DateTime.now().millisecondsSinceEpoch;
  }

  
Future<String?> _mxSendReaction({required String targetEventId, required String emojiKey}) async {
  final client = MatrixService.instance.client;
  if (client == null || !client.isLogged()) return null;

  final roomId = widget.channelHandle;

  // Optimistic overlay so the UI shows the reaction immediately.
  _mxPendingMyReactionByTarget[targetEventId] = emojiKey;
  if (mounted) setState(() {});

  try {
    final room = client.rooms.firstWhere((r) => r.id == roomId);
    final res = await room.sendReaction(targetEventId, emojiKey);
    final reactionEventId = (res is String) ? res : (res?.eventId as dynamic);
    if (reactionEventId is String && reactionEventId.isNotEmpty) {
      _myReactionEventIdsByTarget.putIfAbsent(targetEventId, () => {});
      _myReactionEventIdsByTarget[targetEventId]![emojiKey] = reactionEventId;
    }
    return (reactionEventId is String) ? reactionEventId : null;
  } catch (e) {
    // Roll back optimistic state if sending failed.
    _mxPendingMyReactionByTarget.remove(targetEventId);
    if (mounted) setState(() {});
    if (!mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reaction send failed: $e')),
    );
  }

  return null;
}

  Future<void> _mxRedactReaction({required String reactionEventId}) async {
    final client = MatrixService.instance.client;
    if (client == null || !client.isLogged()) return;

    final roomId = widget.channelHandle;
    try {
      final room = client.rooms.firstWhere((r) => r.id == roomId);
      await room.redactEvent(reactionEventId);
    } catch (_) {
      // ignore
    }
  }

Future<void> _mxEditMessage({required String targetEventId, required String newText}) async {
  final client = MatrixService.instance.client;
  if (client == null || !client.isLogged()) return;

  final roomId = widget.channelHandle;

  // Optimistic overlay so the UI shows the new text immediately.
  _mxPendingEditTextByTarget[targetEventId] = newText;
  if (mounted) setState(() {});

  try {
    final room = client.rooms.firstWhere((r) => r.id == roomId);

    // Matrix Dart SDK supports edits via editEventId parameter.
    // This will send an m.room.message with m.replace relation (MSC2676-style).
    await room.sendTextEvent(
      newText,
      editEventId: targetEventId,
      parseMarkdown: false,
      parseCommands: false,
      displayPendingEvent: true,
    );
  } catch (e) {
    // Roll back optimistic state if sending failed.
    _mxPendingEditTextByTarget.remove(targetEventId);
    if (mounted) setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Edit send failed: $e')),
    );
  }
}




Future<void> _mxRedactMessage({required String targetEventId}) async {
  final client = MatrixService.instance.client;
  if (client == null || !client.isLogged()) return;

  final roomId = widget.channelHandle;

  // Optimistic hide so the UI removes the message immediately.
  _mxPendingRedactions.add(targetEventId);
  if (mounted) setState(() {});

  try {
    final room = client.rooms.firstWhere((r) => r.id == roomId);
    await room.redactEvent(targetEventId);
  } catch (e) {
    _mxPendingRedactions.remove(targetEventId);
    if (mounted) setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Delete failed: $e')),
    );
  }
}




  void _syncUiFromMatrixTimeline({bool newMessageLikely = false}) {
    final t = _mxTimeline;
    final client = MatrixService.instance.client;
    if (t == null || client == null) return;

    final myUserId = client.userID;

    // Build messages first, then apply edits (m.replace) and reactions (m.annotation).
    final ui = <_UiMessage>[];
    final byId = <String, _UiMessage>{};
    final editTextByTarget = <String, String>{};
    final editedAtByTarget = <String, int>{};
    final reactionCounts = <String, Map<String, int>>{}; // targetEventId -> {emojiKey: count}
    final myReactionsByTarget = <String, Set<String>>{};
    final myReactionEventIdByTarget = <String, Map<String, String>>{}; // target -> (emoji -> reactionEventId)


    for (final ev in t.events) {
      final dyn = ev as dynamic;
      final String? type = (dyn.type as String?) ?? (dyn.eventType as String?);
      final String? relType = (dyn.relationshipType as String?);
      final String? relTarget = (dyn.relationshipEventId as String?);

      // Raw relationship info (SDK doesn't always populate relationshipType/relationshipEventId)
      final contentMap = (dyn.content is Map) ? (dyn.content as Map) : const {};
      final relatesMap = (contentMap['m.relates_to'] is Map) ? (contentMap['m.relates_to'] as Map) : const {};
      final String? rawRelType = relatesMap['rel_type']?.toString();
      final String? rawRelTarget = relatesMap['event_id']?.toString();
      final String? effRelType = relType ?? rawRelType;
      final String? effRelTarget = relTarget ?? rawRelTarget;

      // 1) Normal text messages
      if (type == 'm.room.message' && effRelTarget == null) {
        // Prefer content.body; SDK's getDisplayEvent may fallback to event type for service events
        var body = ev.getDisplayEvent(t).body;

        final msgtype = contentMap['msgtype']?.toString();
        // Only show plain text user messages for Telegram bridge rooms.
        if (msgtype != 'm.text') {
          continue;
        }

        if (body.trim().isEmpty || body == type || body.startsWith('m.')) {
          final cb = contentMap['body']?.toString();
          if (cb != null && cb.trim().isNotEmpty) {
            body = cb;
          }
        }

        if (body.trim().isEmpty || body == type || body.startsWith('m.')) continue;

        final createdAtMs = _mxEventTsToMs(dyn.originServerTs);
        final id = (dyn.eventId ?? '${createdAtMs}_${ev.hashCode}').toString();
        final isOut = (myUserId != null && dyn.senderId == myUserId);

        final m = _UiMessage(
          id: id,
          text: body,
          isOutgoing: isOut,
          createdAtMs: createdAtMs,
        );
        ui.add(m);
        byId[id] = m;
        continue;
      }

      // 2) Edits: rel_type = m.replace, target is relationshipEventId
      if (effRelType == 'm.replace' && effRelTarget != null) {
        final content = contentMap;
        final newContent = (content['m.new_content'] is Map) ? (content['m.new_content'] as Map) : null;
        final newBody = (newContent?['body'] ?? content['body'])?.toString();
        if (newBody != null && newBody.trim().isNotEmpty) {
          // Telegram/clients often prefix edited body with '* '. Strip it for UI.
          final cleaned = newBody.startsWith('* ') ? newBody.substring(2) : newBody;
          editTextByTarget[effRelTarget] = cleaned;
          editedAtByTarget[effRelTarget] = _mxEventTsToMs(dyn.originServerTs);
          // Server timeline now contains the edit, no need for optimistic overlay.
          _mxPendingEditTextByTarget.remove(effRelTarget);
        }
        continue;
      }

      // 3) Reactions: type = m.reaction OR rel_type = m.annotation
      if (type == 'm.reaction' || effRelType == 'm.annotation') {
        if (effRelTarget == null) continue;
        final relates = relatesMap;
        final key = relates['key']?.toString();
        if (key == null || key.isEmpty) continue;

        final map = reactionCounts.putIfAbsent(effRelTarget, () => <String, int>{});
        map[key] = (map[key] ?? 0) + 1;

        if (myUserId != null && dyn.senderId == myUserId) {
          final set = myReactionsByTarget.putIfAbsent(effRelTarget, () => <String>{});
          set.add(key);

          final evId = (dyn.eventId ?? dyn.eventID ?? '').toString();
          if (evId.isNotEmpty) {
            final evMap = myReactionEventIdByTarget.putIfAbsent(effRelTarget, () => <String, String>{});
            evMap[key] = evId;
          }

          // Server timeline now contains my reaction(s), no need for optimistic overlay.
          _mxPendingMyReactionByTarget.remove(effRelTarget);
        }
        continue;
      }
    }

    // Apply edits
    for (final entry in editTextByTarget.entries) {
      final targetId = entry.key;
      final msg = byId[targetId];
      if (msg == null) continue;
      msg.text = entry.value;
      msg.editedAtMs = editedAtByTarget[targetId];
    }

    // Apply optimistic edits for targets that haven't arrived via timeline yet.
    // (Do not mutate the map while iterating.)
    final keysToDrop = <String>[];
    for (final entry in _mxPendingEditTextByTarget.entries) {
      final targetId = entry.key;
      if (editTextByTarget.containsKey(targetId)) {
        keysToDrop.add(targetId);
        continue;
      }
      final msg = byId[targetId];
      if (msg == null) continue;
      msg.text = entry.value;
      msg.editedAtMs ??= DateTime.now().millisecondsSinceEpoch;
    }
    for (final k in keysToDrop) {
      _mxPendingEditTextByTarget.remove(k);
    }

    // Apply reactions: show per-emoji chips with counts + know which are mine
    for (final entry in reactionCounts.entries) {
      final targetId = entry.key;
      final msg = byId[targetId];
      if (msg == null) continue;

      final counts = entry.value;
      msg.reactionCounts = Map<String, int>.from(counts);
      _trimReactionGroups(msg);

      // my reactions from server timeline
      final mySet = myReactionsByTarget[targetId];
      if (mySet != null) {
        msg.myReactions = Set<String>.from(mySet);
        // also seed eventIds so we can redact later even after restart
        final evMap = myReactionEventIdByTarget[targetId];
        if (evMap != null) {
          _myReactionEventIdsByTarget[targetId] = Map<String, String>.from(evMap);
        }
      }

      
// apply op// Apply local optimistic MY reactions (authoritative) to avoid flicker.
// Matrix timeline updates can lag behind send/redact; we render exactly what we think is mine,
// and adjust counts by the delta vs server state.
final local = _myReactionsByMessageId[targetId];
if (local != null) {
  final localSet = local.toSet();
  final serverMy = Set<String>.from(msg.myReactions);

  // Start from server counts, then apply delta so totals match local "mine".
  for (final e in localSet) {
    if (!serverMy.contains(e)) {
      msg.reactionCounts[e] = (msg.reactionCounts[e] ?? 0) + 1;
    }
  }
  for (final e in serverMy) {
    if (!localSet.contains(e)) {
      final cur = msg.reactionCounts[e] ?? 0;
      final next = cur - 1;
      if (next <= 0) {
        msg.reactionCounts.remove(e);
      } else {
        msg.reactionCounts[e] = next;
      }
    }
  }
  msg.myReactions = localSet;
}

    }

    // Keep legacy list in sync (used by quick panel / older code paths)
    for (final m in ui) {
      if (m.myReactions.isNotEmpty) {
        m.reactions = List<String>.from(m.myReactions.take(3));
      } else {
        m.reactions = [];
      }
    }

// Apply optimistic reactions for targets that don't yet appear in the timeline.
    for (final msg in ui) {
      if (msg.reactions.isNotEmpty) continue;
      final pending = _mxPendingMyReactionByTarget[msg.id];
      if (pending != null && pending.isNotEmpty) {
        msg.reactions = [pending];
      }
    }

    // Apply optimistic reactions for targets that haven't arrived via timeline yet.
    for (final entry in _mxPendingMyReactionByTarget.entries) {
      final targetId = entry.key;
      final msg = byId[targetId];
      if (msg == null) continue;
      // Don't override a real reaction rendered from timeline.
      msg.reactions = msg.reactions.isNotEmpty ? msg.reactions : [entry.value];
    }

    ui.sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));

    // Track whether we should show the "new messages" jump button.
    final prevCount = _messages.length;
    setState(() {
      _messages
        ..clear()
        ..addAll(ui);
    });

    if (newMessageLikely && ui.length > prevCount) {
      _maybeAutoScroll(force: false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    });
  }

  void _maybeAutoScroll({required bool force}) {
    // force: used for отправка сообщения пользователем (ожидаемо прыгнуть вниз)
    if (force || _isAtBottom) {
      _pendingNewMessages = 0;
      _scrollToBottom();
      return;
    }
    if (mounted) {
      setState(() {
        _pendingNewMessages += 1;
      });
    }
  }

  Future<void> _autoLoadFullHistoryIfEnabled() async {
    if (_autoLoadingFullHistory) return;
    if (!AppSettingsStore.instance.autoLoadFullHistoryOnOpen.value) return;
    final timeline = _mxTimeline;
    if (timeline == null) return;

    _autoLoadingFullHistory = true;
    if (mounted) {
      setState(() {
        _mxLoadingHistory = true;
      });
    }

    int prevLen = timeline.events.length;
    // Защита от бесконечного цикла: максимум 200 запросов.
    for (int i = 0; i < 200; i++) {
      try {
        await timeline.requestHistory();
      } catch (_) {
        break;
      }

      // Дадим таймлайну/SDK обработать результат.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      _syncUiFromMatrixTimeline();

      final nowLen = timeline.events.length;
      if (nowLen <= prevLen) {
        break; // больше нечего подгружать
      }
      prevLen = nowLen;
    }

    if (mounted) {
      setState(() {
        _mxLoadingHistory = false;
      });
    }
    _autoLoadingFullHistory = false;
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final convId = _effectiveConversationId ?? widget.conversationId;
    if (convId == null) return;

    final ts = DateTime.now().millisecondsSinceEpoch;

    // 1) UI
    if (mounted) {
      setState(() {
        _messages.add(_UiMessage(id: "msg_${convId}_$ts", text: text, isOutgoing: true, createdAtMs: ts));
      });
    }
    _controller.clear();
    _maybeAutoScroll(force: true);

    // 2) Persist / Send
    if (_isMatrixRoom) {
      try {
        final client = MatrixService.instance.client;
        if (client != null && client.isLogged()) {
          final room = client.rooms.firstWhere((r) => r.id == widget.channelHandle);
          await room.sendTextEvent(text);
        }
      } catch (_) {
        // Ignore for now; UI will still show optimistic message.
      }
    } else {
      await DbService.instance.addMessage(
        contactId: widget.contactId,
        conversationId: convId,
        isOutgoing: true,
        text: text,
        createdAtMs: ts,
      );
    }

    
    // _scheduleAutoReply(original: text); // disabled
    // 3) Обновим диалог (lastMessage/updatedAt) и поднимем его наверх в списке
    ConversationStore.instance.touchConversation(
      convId,
      lastMessage: text,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(ts),
      unreadCount: 0,
    );
  }

  Future<void> _scheduleAutoReply({required String original}) async {
    // Auto-reply disabled.
    return;
  }
  @override
  
  String _fmtTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    if (inset != _lastViewInset) {
      _lastViewInset = inset;
      // Keyboard appeared/disappeared.
      _scrollToBottomSoon();
    }

    return WillPopScope(
      onWillPop: () async {
        if (_isEmojiOpen || _showEmojiKeyboard) {
          setState(() {
            _isEmojiOpen = false;
            _showEmojiKeyboard = false;
          });
          _focusNode.requestFocus();
          return false;
        }
        return true;
      },
      child: Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: _selectionMode
          ? AppBar(
              backgroundColor: widget.channelSource.color,

              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              ),
              title: Text(_selectedIds.length.toString()),
              actions: [
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: _selectedIds.isEmpty ? null : _selectionActionCopy,
                ),
                IconButton(
                  icon: const Icon(Icons.forward),
                  onPressed: () {
                    _exitSelectionMode();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скоро 🙂')),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _selectedIds.isEmpty ? null : _selectionActionDelete,
                ),
              ],
            )
          : AppBar(
              backgroundColor: widget.channelSource.color,

              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              titleSpacing: 0,
              title: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ContactPage(contactId: widget.contactId),
                  ),
                );
              },
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white.withOpacity(0.22),
                    child: Icon(
                      widget.channelSource.icon,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        // Rebuild when contacts store updates.
                        ref.watch(contactsVersionProvider);
                        final store = ref.read(contactStoreProvider);
                        final contact = store.tryGet(widget.contactId);

                        final title = (contact?.preferredTitle.trim().isNotEmpty ?? false)
                            ? contact!.preferredTitle.trim()
                            : widget.channelHandle;

                        final subtitle = '${widget.channelSource.label} · ${widget.channelHandle}';

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withOpacity(0.85),
                                  ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
              actions: [
                const Icon(Icons.videocam_outlined),
                const SizedBox(width: 10),
                const Icon(Icons.call_outlined),
                const SizedBox(width: 10),
                PopupMenuButton<_ChatMenuAction>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (a) {
                    switch (a) {
                      case _ChatMenuAction.linkToContact:
                        _openLinkToContactSheet();
                        break;
                    }
                  },
                  itemBuilder: (context) {
                    final canLink = _effectiveConversationId != null && widget.channelHandle.startsWith('!');
                    return [
                      PopupMenuItem<_ChatMenuAction>(
                        value: _ChatMenuAction.linkToContact,
                        enabled: canLink,
                        child: const Text('Привязать к контакту'),
                      ),
                    ];
                  },
                ),
                const SizedBox(width: 6),
              ],
            ),
        body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset('assets/chat_bg.png', fit: BoxFit.cover),
                    ),
                    if (_isMatrixRoomAsTelegram && _mxTimeline != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 6,
                        child: SafeArea(
                          bottom: false,
                          child: Center(
                            child: TextButton(
                              onPressed: _mxLoadingHistory
                                  ? null
                                  : () async {
                                      final t = _mxTimeline;
                                      if (t == null) return;
                                      setState(() => _mxLoadingHistory = true);
                                      try {
                                        await t.requestHistory();
                                      } catch (_) {
                                        // ignore
                                      }
                                      if (!mounted) return;
                                      setState(() => _mxLoadingHistory = false);
                                      _syncUiFromMatrixTimeline();
                                    },
                              child: Text(_mxLoadingHistory ? 'Загрузка…' : 'Загрузить ещё'),
                            ),
                          ),
                        ),
                      ),
                    ListView.builder(
                      key: _listKey,
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      final bool showDayHeader;
                      if (index == 0) {
                        showDayHeader = true;
                      } else {
                        final prev = _messages[index - 1];
                        showDayHeader = !_isSameDay(m.createdAtMs, prev.createdAtMs);
                      }


                      final headerText = _formatDayHeader(m.createdAtMs);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDayHeader)
                          _DayHeader(
                            key: _dayHeaderKeys.putIfAbsent(headerText, () => GlobalKey()),
                            text: headerText,
                          ),
                          _MessageBubble(
                            message: m,
                            selected: _selectedIds.contains(m.id),
                            onTap: () => _onMessageTap(m),
                            onReactionTap: (msg, emo) => _onReactionChipTap(msg, emo),
                            onLongPress: () => _onMessageLongPress(m),
                          ),
                        ],
                      );
                    },
                    ),                    IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: (_stickyVisible && _stickyDayLabel != null) ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 120),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _stickyDayLabel ?? '',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // "New messages jump-to-bottom button (only when user is not at bottom)
                    if (!_isAtBottom && _pendingNewMessages > 0)
                      Positioned(
                        right: 14,
                        bottom: 14,
                        child: SafeArea(
                          minimum: const EdgeInsets.only(bottom: 56),
                          child: Material(
                            elevation: 2,
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () {
                                if (mounted) {
                                  setState(() {
                                    _pendingNewMessages = 0;
                                  });
                                }
                                _scrollToBottom();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.arrow_downward, size: 18),
                                    if (_pendingNewMessages > 1) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        _pendingNewMessages.toString(),
                                        style: Theme.of(context).textTheme.labelLarge,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
          ),
          _buildInput(),
          if (_showEmojiKeyboard)
            SizedBox(
              height: _kEmojiKeyboardHeight,
              child: FullEmojiPicker(
                onEmojiSelected: (e) => _insertEmojiToInput(e.emoji),
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildInput() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Shortcuts(
          shortcuts: {
            LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter): _SendIntent(),
            LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.enter): _SendIntent(),
          },
          child: Actions(
            actions: {
              _SendIntent: CallbackAction<_SendIntent>(
                onInvoke: (_) {
                  _sendMessage();
                  return null;
                },
              ),
            },
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                          color: Colors.black.withOpacity(0.08),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(_showEmojiKeyboard ? Icons.keyboard : Icons.emoji_emotions_outlined),
                          onPressed: _toggleEmojiKeyboard,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _inputFocus,
                            minLines: 1,
                            maxLines: 5,
                            onTap: () {
                              if (_showEmojiKeyboard) {
                                setState(() => _showEmojiKeyboard = false);
                              }
                            },
                            decoration: const InputDecoration(
                              hintText: 'Сообщение',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.attach_file),
                          onPressed: () {},
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.camera_alt_outlined),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Material(
                    color: const Color(0xFF25D366),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _hasText ? _sendMessage : () {},
                      child: Icon(
                        _hasText ? Icons.send : Icons.mic,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }



    void _exitSelectionMode() {
    if (!_selectionMode) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  Future<void> _onMessageTap(_UiMessage m) async {
    if (_selectionMode) {
      _toggleSelected(m.id);
      return;
    }
    await _showMessageMenu(m);
  }

  Future<void> _onMessageLongPress(_UiMessage m) async {
    if (!_selectionMode) {
      setState(() {
        _selectionMode = true;
        _selectedIds.clear();
        _selectedIds.add(m.id);
      });
      return;
    }
    _toggleSelected(m.id);
  }

  Future<void> _showMessageMenu(_UiMessage m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        Widget reactionButton(String emoji) {
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.pop(ctx, 'react:$emoji'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          );
        }

        Widget expandReactionsButton() {
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => Navigator.pop(ctx, 'react_more'),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceVariant.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          );
        }

        final isMx = _isMatrixRoomAsTelegram;
        final canEdit = m.isOutgoing;
        final canDelete = m.isOutgoing;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: FutureBuilder<List<String>>(
                  future: DbService.instance.loadTopEmojis(limit: 7),
                  builder: (context, snap) {
                    final top = (snap.data ?? const <String>[]).where((e) => e.trim().isNotEmpty).toList();
                    // Default fallback set (Telegram-like): must always exist.
                    final fallback = const ['❤️', '😁', '😢', '🥰', '💘', '😡', '😱'];
                    final emojis = (top.isEmpty ? fallback : top).take(7).toList(growable: false);
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final e in emojis) reactionButton(e),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        expandReactionsButton(),
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Ответить'),
                onTap: () => Navigator.pop(ctx, 'reply'),
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Копировать'),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Переслать'),
                onTap: () => Navigator.pop(ctx, 'forward'),
              ),
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: const Text('Закрепить'),
                onTap: () => Navigator.pop(ctx, 'pin'),
              ),
ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('Добавить в заметки контакта'),
                onTap: () => Navigator.pop(ctx, 'note'),
              ),
              if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Изменить'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              if (canDelete)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Удалить'),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
              const SizedBox(height: 8),
            
                ],
              ),
            ),
          ),
        );
},
    );

    if (!mounted || action == null) return;

    // Reactions
    if (action.startsWith('react:')) {
      final emoji = action.substring('react:'.length);
      await _applyReaction(m, emoji);
      return;
    }

    if (action == 'react_more') {
      final picked = await _showEmojiPickerForReaction(m.reaction);
      if (!mounted || picked == null) return;
      await _applyReaction(m, picked);
      return;
    }

    switch (action) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: m.text));
        break;
      case 'note':
        await _addMessageToContactNotes(m.text);
        break;
      case 'delete':
        await _deleteMessageById(m.id);
        break;
      case 'edit':
        await _editMessage(m);
        break;
      case 'reply':
      case 'forward':
      case 'pin':
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Скоро 🙂')),
          );
        }
        break;
    }
  }

  /// Apply a reaction to a message (Telegram/WhatsApp-like behavior).
  ///
  /// Important detail for Matrix-bridged rooms:
  /// the timeline may re-sync immediately after the picker closes.
  /// We therefore set the optimistic overlay *before* awaiting network calls.
  
  void _setLocalReactions(_UiMessage m, List<String> reactions) {
    if (reactions.isEmpty) {
      _myReactionsByMessageId.remove(m.id);
    } else {
      _myReactionsByMessageId[m.id] = List<String>.from(reactions);
    }
    if (mounted) {
      setState(() => m.reactions = List<String>.from(reactions));
    }
  }

  void _trimReactionGroups(_UiMessage message, {String? preferKeepEmoji}) {
    // Keep at most 3 different reaction emojis on the bubble (FIFO by insertion order).
    const int maxGroups = 3;
    if (message.reactionCounts.length <= maxGroups) return;

    // Remove oldest keys first, but try to keep the newly added emoji if provided.
    while (message.reactionCounts.length > maxGroups) {
      final oldest = message.reactionCounts.keys.first;
      if (preferKeepEmoji != null && oldest == preferKeepEmoji && message.reactionCounts.length > 1) {
        // If the oldest is the one we prefer to keep, rotate by removing the next oldest instead.
        final keys = message.reactionCounts.keys.toList(growable: false);
        final candidate = keys.length > 1 ? keys[1] : oldest;
        message.reactionCounts.remove(candidate);
        message.myReactions.remove(candidate);
        _myReactionsByMessageId[message.id]?.remove(candidate);
        continue;
      }
      message.reactionCounts.remove(oldest);
      message.myReactions.remove(oldest);
      _myReactionsByMessageId[message.id]?.remove(oldest);
    }
  }



  Future<void> _toggleReactionChip(_UiMessage message, String emoji) async {
    // Determine whether this emoji is mine using local-authoritative cache first.
    final mineList = List<String>.from(_myReactionsByMessageId[message.id] ?? message.myReactions.toList());
    final isMine = mineList.contains(emoji);

    if (isMine) {
      // remove my reaction
      mineList.remove(emoji);
      message.myReactions = mineList.toSet();
      _myReactionsByMessageId[message.id] = List<String>.from(mineList);
      // decrement count
      final cur = message.reactionCounts[emoji] ?? 1;
      if (cur <= 1) {
        message.reactionCounts.remove(emoji);
      } else {
        message.reactionCounts[emoji] = cur - 1;
      }
      if (mounted) setState(() {});

      if (_isMatrixRoomAsTelegram) {
        final evId = _myReactionEventIdsByTarget[message.id]?[emoji];
        if (evId != null) {
          await _mxRedactReaction(reactionEventId: evId);
        }
      }
      return;
    }

    // add same emoji (also counts as mine)
    const int maxReactions = 3;
    final mine = List<String>.from(mineList);
    
    if (mine.length >= maxReactions) {
      final oldest = mine.first;
      mine.removeAt(0);
      message.myReactions.remove(oldest);
      // decrement oldest count
      final oc = message.reactionCounts[oldest] ?? 1;
      if (oc <= 1) {
        message.reactionCounts.remove(oldest);
      } else {
        message.reactionCounts[oldest] = oc - 1;
      }
      if (_isMatrixRoomAsTelegram) {
        final evOld = _myReactionEventIdsByTarget[message.id]?[oldest];
        if (evOld != null) {
          await _mxRedactReaction(reactionEventId: evOld);
        }
      }
    }

    mine.add(emoji);
    message.myReactions = mine.toSet();
    // Enforce global FIFO max 3 reaction emojis on bubble.
    _myReactionsByMessageId[message.id] = List<String>.from(mine);
    message.reactionCounts[emoji] = (message.reactionCounts[emoji] ?? 0) + 1;
    _trimReactionGroups(message, preferKeepEmoji: emoji);

    // keep legacy list
    message.reactions = List<String>.from(message.myReactions.take(3));

    if (mounted) setState(() {});

    if (_isMatrixRoomAsTelegram) {
      final evId = await _mxSendReaction(targetEventId: message.id, emojiKey: emoji);
      if (evId != null) {
        _myReactionEventIdsByTarget.putIfAbsent(message.id, () => <String, String>{})[emoji] = evId;
      }
    } else {
      await DbService.instance.setMessageReaction(
        messageId: message.id,
        reaction: message.reactions.isNotEmpty ? message.reactions.first : null,
      );
    }
  }

Future<void> _applyReaction(_UiMessage m, String emoji) async {
    const int maxReactions = 3;
    final before = List<String>.from(_myReactionsByMessageId[m.id] ?? m.reactions);
    final after = List<String>.from(before);

    // Toggle / add / replace-oldest (Telegram Premium-like FIFO)
    if (after.contains(emoji)) {
      after.remove(emoji);
    } else {
      if (after.length < maxReactions) {
        after.add(emoji);
      } else {
        // replace oldest
        after.removeAt(0);
        after.add(emoji);
      }
    }

    // Update local map + UI immediately (single source of truth for OUR reactions)
    _setLocalReactions(m, after);

    // Persist emoji usage so quick panel reflects usage.
    await DbService.instance.bumpEmojiUsage(emoji);

    final removed = before.where((e) => !after.contains(e)).toList();
    final added = after.where((e) => !before.contains(e)).toList();

    // Matrix rooms (Telegram bridge): send EVERY added reaction; redact removed reaction events if we know them.
    if (_isMatrixRoom) {
      // optimistic overlay: keep last as "my" (legacy UI)
      if (after.isNotEmpty) {
        _mxPendingMyReactionByTarget[m.id] = after.last;
      } else {
        _mxPendingMyReactionByTarget.remove(m.id);
      }
      if (mounted) setState(() {});

      // Redact removed reactions (best effort)
      final byEmoji = _myReactionEventIdsByTarget[m.id];
      if (byEmoji != null) {
        for (final r in removed) {
          final evId = byEmoji[r];
          if (evId != null && evId.isNotEmpty && !m.id.startsWith('msg_')) {
            await _mxRedactReaction(reactionEventId: evId);
            byEmoji.remove(r);
          }
        }
        if (byEmoji.isEmpty) _myReactionEventIdsByTarget.remove(m.id);
      }

      // Send added reactions
      for (final a in added) {
        if (m.id.startsWith('msg_')) continue; // local-only temp message
        await _mxSendReaction(targetEventId: m.id, emojiKey: a);
      }
      return;
    }

    // Non-Matrix chats: keep backwards compatibility with DB single reaction
    final dbReaction = after.isNotEmpty ? after.first : null;
    await DbService.instance.setMessageReaction(messageId: m.id, reaction: dbReaction);
  }


  
  Future<void> _onReactionChipTap(_UiMessage message, String emoji) async {
    // New rule:
    // - If it's my own reaction -> remove on tap.
    // - If it's someone else's reaction -> repeat it (add mine) on tap.
    await _toggleReactionChip(message, emoji);
  }

Future<String?> _showEmojiPickerForReaction(String? current) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.65,
            child: FullEmojiPicker(
              onEmojiSelected: (e) => Navigator.pop(ctx, e.emoji),
            ),
          ),
        );
      },
    );
  }

  Future<void> _addMessageToContactNotes(String text) async {
    final store = ref.read(contactStoreProvider);
    await store.addNote(widget.contactId, text);
  }

  

Future<void> _editMessage(_UiMessage m) async {
  if (!m.isOutgoing) return;

  // For Matrix rooms-as-Telegram, we can only edit real Matrix events (not local optimistic ids).
  final isMatrix = _isMatrixRoom;
  if (isMatrix && m.id.startsWith('msg_')) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подожди: сообщение ещё не ушло в Matrix, редактирование недоступно.')),
      );
    }
    return;
  }

  final controller = TextEditingController(text: m.text);
  final newText = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Изменить сообщение'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );

  if (newText == null) return;
  if (newText.isEmpty || newText == m.text) return;

  final ts = DateTime.now().millisecondsSinceEpoch;

  setState(() {
    m.text = newText;
    m.editedAtMs = ts;
  });

  if (isMatrix) {
    await _mxEditMessage(targetEventId: m.id, newText: newText);
  } else {
    await DbService.instance.editMessage(messageId: m.id, newText: newText, editedAtMs: ts);
  }
}

Future<void> _deleteMessageById(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;

    // Optimistic UI remove
    setState(() {
      _messages.removeWhere((e) => e.id == id);
      _selectedIds.remove(id);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });

    // Local DB cleanup (for non-matrix messages this is the primary delete)
    await DbService.instance.deleteMessage(messageId: id);

    // For Matrix rooms bridged as Telegram: try to redact the event on the server too.
    if (_isMatrixRoomAsTelegram && !id.startsWith('msg_')) {
      await _mxRedactMessage(targetEventId: id);
    }
  }

  Future<void> _selectionActionCopy() async {
    final selected = _messages.where((m) => _selectedIds.contains(m.id)).toList();
    selected.sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
    final combined = selected.map((m) => m.text).join('\n');
    Clipboard.setData(ClipboardData(text: combined));
    _exitSelectionMode();
  }

  Future<void> _selectionActionDelete() async {
    final ids = _selectedIds.toList();
    for (final id in ids) {
      await _deleteMessageById(id);
    }
    _exitSelectionMode();
  }


  bool _isSameDay(int aMs, int bMs) {
    final a = DateTime.fromMillisecondsSinceEpoch(aMs);
    final b = DateTime.fromMillisecondsSinceEpoch(bMs);
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDayHeader(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    String dow(DateTime d) {
      switch (d.weekday) {
        case DateTime.monday:
          return 'Пн';
        case DateTime.tuesday:
          return 'Вт';
        case DateTime.wednesday:
          return 'Ср';
        case DateTime.thursday:
          return 'Чт';
        case DateTime.friday:
          return 'Пт';
        case DateTime.saturday:
          return 'Сб';
        case DateTime.sunday:
          return 'Вс';
      }
      return '';
    }

    String datePart(DateTime d) {
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final base = '$dd.$mm';
      if (d.year != now.year) return '$base.${d.year}';
      return base;
    }

    if (_isSameDay(ms, now.millisecondsSinceEpoch)) {
      return 'Сегодня (${datePart(dt)}, ${dow(dt)})';
    }
    if (_isSameDay(ms, yesterday.millisecondsSinceEpoch)) {
      return 'Вчера (${datePart(dt)}, ${dow(dt)})';
    }
    return '${datePart(dt)}, ${dow(dt)}';
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

class _DayHeader extends StatelessWidget {
  final String text;
  const _DayHeader({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  static String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  final _UiMessage message;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final void Function(_UiMessage, String)? onReactionTap;

  const _MessageBubble({
    required this.message,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.onReactionTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOut = message.isOutgoing;
    final align = isOut ? Alignment.centerRight : Alignment.centerLeft;

    // WhatsApp-like palette
    final bubbleColor = isOut ? const Color(0xFFDCF8C6) : Colors.white;
    final textColor = Colors.black87;

    // WhatsApp shows a tiny shadow + subtle border on light backgrounds.
    final baseShadow = <BoxShadow>[
      BoxShadow(
        blurRadius: 6,
        spreadRadius: 0,
        offset: const Offset(0, 1),
        color: Colors.black.withOpacity(0.08),
      ),
    ];

    final border = selected
        ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
        : null;

    final footer = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.editedAtMs != null)
          Text(
            'Изм.',
            style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(0.55)),
          ),
        if (message.editedAtMs != null) const SizedBox(width: 6),
        Text(
          _formatTime(message.createdAtMs),
          style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(0.55)),
        ),
        if (isOut) ...[
          const SizedBox(width: 6),
          Icon(Icons.done_all, size: 16, color: Colors.blueAccent.withOpacity(0.9)),
        ],
      ],
    );


    // Rounded rectangle bubble (NO tails), WhatsApp-like.
    final bubble = Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(16),
            border: border ?? Border.all(color: Colors.black.withOpacity(0.05)),
            boxShadow: baseShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Stack(
              children: [
                // Reserve space for the footer so it never overlaps text,
                // and keep it stable even for 1-letter messages.
                Padding(
                  padding: EdgeInsets.only(
                    right: isOut ? 60 : 44,
                    bottom: 18,
                  ),
                  child: Text(
                    message.text,
                    style: const TextStyle(color: Colors.black87, height: 1.25, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 2),
                Positioned(
                  right: 6,
                  bottom: 4,
                  child: footer,
                ),
              ],
            ),
          ),
        ),
        ),
        
if (message.reactionCounts.isNotEmpty)
  Positioned(
    left: isOut ? null : 8,
    right: isOut ? 8 : null,
    // Slight overlap like WhatsApp/Telegram, but keep it tight.
    bottom: -30,
    child: Wrap(
      spacing: 4,
      runSpacing: 3,
      children: [
        for (final entry in message.reactionCounts.entries)
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onReactionTap?.call(message, entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: message.myReactions.contains(entry.key)
                    ? Colors.white.withOpacity(0.95)
                    : Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(999),
                boxShadow: baseShadow,
                border: Border.all(color: Colors.black.withOpacity(0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(entry.key, style: const TextStyle(fontSize: 14)),
                  if (entry.value > 1) ...[
                    const SizedBox(width: 6),
                    Text(
                      entry.value.toString(),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    ),
  ),
      ],
    );

    // IMPORTANT: Make bubble alignment *strict* (Telegram/WhatsApp-like)
    // Outgoing messages: always stick to the right edge.
    // Incoming messages: always stick to the left edge.
    return Padding(
      padding: EdgeInsets.only(
        left: isOut ? 54 : 8,
        right: isOut ? 8 : 54,
        top: 2,
        bottom: message.reactionCounts.isNotEmpty ? 20 : 2,
      ),
      child: Row(
        mainAxisAlignment: isOut ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              // Keep short bubbles a bit wider so the footer always sits inside,
              // but don't force them to be huge.
              minWidth: 122,
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Padding(
                // Reserve space for reaction pill overlapping under the bubble.
                padding: EdgeInsets.only(bottom: message.reactionCounts.isNotEmpty ? 18 : 0),
                child: bubble,
              ),
          ),
        ],
      ),
    );
  }
}

class _UiMessage {
  final String id;
  String text;
  final bool isOutgoing;
  final int createdAtMs;
  int? editedAtMs;

  List<String> reactions;
  Map<String, int> reactionCounts = {};
  Set<String> myReactions = {};

  String? get reaction => reactions.isNotEmpty ? reactions.first : null;
  set reaction(String? v) {
    reactions = v == null || v.isEmpty ? [] : [v];
  }

  _UiMessage({
    required this.id,
    required this.text,
    required this.isOutgoing,
    required this.createdAtMs,
    this.editedAtMs,
    String? reaction,
    List<String>? reactions,
  }) : reactions = reactions ?? (reaction != null ? [reaction] : []);
}


class _EmojiItem {
  final String emoji;
  final List<String> keys;
  const _EmojiItem(this.emoji, this.keys);
}

// "Стандартный" набор (не все Unicode, но достаточно широкий и привычный).
// Поиск работает по ключам (EN/RU) + по самому эмодзи.
const List<_EmojiItem> _kEmojiCatalog = [
  _EmojiItem('❤️', ['heart', 'love', 'сердце', 'любовь', 'лайк']),
  _EmojiItem('😍', ['love', 'crush', 'eyes', 'влюбл', 'красиво']),
  _EmojiItem('😁', ['grin', 'smile', 'радость', 'смех']),
  _EmojiItem('😢', ['cry', 'sad', 'слезы', 'грусть']),
  _EmojiItem('🥰', ['love', 'cute', 'милота', 'обнимаю']),
  _EmojiItem('💘', ['heart', 'arrow', 'любовь', 'стрела']),
  _EmojiItem('😡', ['angry', 'mad', 'злой', 'бесит']),
  _EmojiItem('😱', ['shock', 'scared', 'ужас', 'шок']),
  _EmojiItem('👍', ['thumbs', 'like', 'ok', 'класс', 'норм']),
  _EmojiItem('👎', ['thumbs', 'dislike', 'плохо', 'не']),
  _EmojiItem('🔥', ['fire', 'hot', 'огонь', 'жарко', 'круто']),
  _EmojiItem('🎉', ['party', 'celebrate', 'праздник', 'ура']),
  _EmojiItem('😂', ['lol', 'laugh', 'смех', 'ржу']),
  _EmojiItem('🙂', ['smile', 'ok', 'норм', 'улыбка']),
  _EmojiItem('😉', ['wink', 'подмиг']),
  _EmojiItem('🤔', ['think', 'hmm', 'думаю', 'хм']),
  _EmojiItem('👏', ['clap', 'браво', 'аплодис']),
  _EmojiItem('🙏', ['pray', 'please', 'спасибо', 'прошу']),
  _EmojiItem('🤝', ['handshake', 'сделка', 'договор']),
  _EmojiItem('💯', ['100', 'perfect', 'сотка', 'идеал']),
  _EmojiItem('✅', ['check', 'ok', 'готово', 'да']),
  _EmojiItem('❌', ['x', 'no', 'нет', 'отмена']),
  _EmojiItem('😴', ['sleep', 'сплю', 'устал']),
  _EmojiItem('🤯', ['mindblown', 'взрыв', 'офиг']),
  _EmojiItem('😎', ['cool', 'очки', 'крутой']),
  _EmojiItem('😭', ['cry', 'плачу', 'рыдаю']),
  _EmojiItem('😅', ['sweat', 'неловко', 'ха-ха']),
  _EmojiItem('😐', ['neutral', 'без эмоций', 'мм']),
  _EmojiItem('😬', ['grimace', 'страшно', 'неловко']),
  _EmojiItem('🤦‍♂️', ['facepalm', 'рукалицо', 'капец']),
  _EmojiItem('🤷‍♂️', ['shrug', 'не знаю', 'пофиг']),
  _EmojiItem('🤍', ['white heart', 'сердце']),
  _EmojiItem('💔', ['broken heart', 'разбит', 'жаль']),
  _EmojiItem('💙', ['blue heart', 'сердце']),
  _EmojiItem('💚', ['green heart', 'сердце']),
  _EmojiItem('💛', ['yellow heart', 'сердце']),
  _EmojiItem('🧡', ['orange heart', 'сердце']),
  _EmojiItem('💜', ['purple heart', 'сердце']),
  _EmojiItem('💩', ['poop', 'кака', 'шутка']),
  _EmojiItem('👀', ['eyes', 'смотрю', 'вижу']),
  _EmojiItem('🙈', ['monkey', 'стыд', 'не вижу']),
  _EmojiItem('🙉', ['monkey', 'не слышу']),
  _EmojiItem('🙊', ['monkey', 'молчу']),
  _EmojiItem('✨', ['sparkles', 'магия', 'вау']),
  _EmojiItem('⚡', ['lightning', 'молния', 'быстро']),
  _EmojiItem('🌿', ['leaf', 'зелень', 'природа']),
  _EmojiItem('🌞', ['sun', 'сол', 'шамс', 'shams', 'солнце']),
  _EmojiItem('🍌', ['banana', 'банан']),
  _EmojiItem('🍕', ['pizza', 'пицца']),
  _EmojiItem('🌭', ['hotdog', 'хотдог']),
  _EmojiItem('☕', ['coffee', 'кофе', 'café']),
  _EmojiItem('🍰', ['cake', 'торт']),
  _EmojiItem('🥩', ['meat', 'мясо']),
  _EmojiItem('🐳', ['whale', 'кит']),
  _EmojiItem('🗿', ['moai', 'моаи', 'камень']),
];

class _EmojiPickerSheet extends StatefulWidget {
  final String initialQuery;
  final ValueChanged<String> onPick;
  const _EmojiPickerSheet({
    super.key,
    required this.initialQuery,
    required this.onPick,
  });

  @override
  State<_EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<_EmojiPickerSheet> {
  late final TextEditingController _c;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialQuery);
    _q = widget.initialQuery;
    _c.addListener(() {
      final next = _c.text.trim();
      if (next == _q) return;
      setState(() => _q = next);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  List<_EmojiItem> _filter(List<_EmojiItem> all) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((e) {
      if (e.emoji.contains(q)) return true;
      return e.keys.any((k) => k.toLowerCase().contains(q));
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter(_kEmojiCatalog);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            controller: _c,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Поиск',
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.45),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final e = filtered[i].emoji;
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => widget.onPick(e),
                child: Center(
                  child: Text(
                    e,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// --------------------
// Contact picker sheet
// --------------------
class _ContactPickerSheet extends ConsumerStatefulWidget {
  const _ContactPickerSheet({required this.initialSelectedId});

  final String initialSelectedId;

  @override
  ConsumerState<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends ConsumerState<_ContactPickerSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Trigger rebuilds when the in-memory contact store changes.
    ref.watch(contactsVersionProvider);

    final store = ref.read(contactStoreProvider);
    final q = _search.text.trim().toLowerCase();

    final contacts = store.all
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    final filtered = q.isEmpty
        ? contacts
        : contacts.where((c) {
            final dn = c.displayName.toLowerCase();
            final fn = (c.firstName ?? '').toLowerCase();
            final ln = (c.lastName ?? '').toLowerCase();
            final comp = (c.company ?? '').toLowerCase();
            return dn.contains(q) || fn.contains(q) || ln.contains(q) || comp.contains(q);
          }).toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Text(
                'Привязать к контакту',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Поиск контакта',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final c = filtered[i];
                    final selected = c.id == widget.initialSelectedId;
                    return ListTile(
                      title: Text(c.displayName.isNotEmpty ? c.displayName : 'Без имени'),
                      subtitle: (c.company != null && c.company!.trim().isNotEmpty)
                          ? Text(c.company!.trim())
                          : null,
                      trailing: selected ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.of(context).pop(c.id),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
