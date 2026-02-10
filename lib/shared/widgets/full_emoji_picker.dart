import 'dart:convert';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Custom emoji picker "like WhatsApp":
/// - Search icon; input field appears only after tap.
/// - Recents at top (28 max). No empty space above.
/// - One continuous vertical scroll (recents -> categories sequentially).
/// - Bottom categories act like anchors.
/// - Search uses assets/emoji/annotations_{en,ru}.json (supports simple or CLDR formats).
class FullEmojiPicker extends StatefulWidget {
  final ValueChanged<Emoji> onEmojiSelected;
  final TextStyle? emojiTextStyle;
  final String searchHint;

  const FullEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    this.emojiTextStyle,
    this.searchHint = 'Поиск',
  });

  @override
  State<FullEmojiPicker> createState() => _FullEmojiPickerState();
}

class _FullEmojiPickerState extends State<FullEmojiPicker> {
  static const int _columns = 9;
  static const int _recentsLimit = 28;
  static const double _hSpace = 6;
  static const double _vSpace = 6;
  static const double _emojiFontSize = 26;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _searchMode = false;
  Future<List<Emoji>>? _searchFuture;

  // recents (local)
  final List<Emoji> _recents = <Emoji>[];

  // anchors
  final Map<String, GlobalKey> _sectionKeys = <String, GlobalKey>{};

  // index (emoji -> normalized keywords)
  bool _indexReady = false;
  String? _indexErr;
  int _enCount = 0;
  int _ruCount = 0;
  final Map<String, String> _index = <String, String>{};

  @override
  void initState() {
    super.initState();
    _initIndex();
    _searchCtrl.addListener(() {
      _searchFuture = null;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // remove variation selectors + skin tones
  String _baseEmoji(String s) {
    if (s.isEmpty) return s;
    s = s.replaceAll('\uFE0F', '').replaceAll('\uFE0E', '');
    const tones = ['\u{1F3FB}', '\u{1F3FC}', '\u{1F3FD}', '\u{1F3FE}', '\u{1F3FF}'];
    for (final t in tones) {
      s = s.replaceAll(t, '');
    }
    return s;
  }

  String _norm(String s) {
    final lower = s.toLowerCase().replaceAll('ё', 'е');
    return lower
        .replaceAll(RegExp(r'[^a-z0-9а-я ]+', unicode: true), ' ')
        .replaceAll(RegExp(r' +'), ' ')
        .trim();
  }

  Map<String, List<String>> _extractAnnMap(dynamic root) {
    // 1) Simple: { "😀": ["улыбка", ...], ... }
    // 2) CLDR-like: { "annotations": { "annotations": { "😀": {"default":[...],"tts":[...]}, ... } } }
    if (root is Map<String, dynamic>) {
      if (root.containsKey('annotations')) {
        final ann1 = root['annotations'];
        if (ann1 is Map && ann1['annotations'] is Map) {
          final ann2 = ann1['annotations'] as Map;
          final out = <String, List<String>>{};
          for (final entry in ann2.entries) {
            final key = entry.key?.toString() ?? '';
            final v = entry.value;
            final buf = <String>[];
            if (v is Map) {
              final def = v['default'];
              final tts = v['tts'];
              if (def is List) buf.addAll(def.map((e) => e.toString()));
              if (tts is List) buf.addAll(tts.map((e) => e.toString()));
              if (def is String) buf.add(def);
              if (tts is String) buf.add(tts);
            }
            if (key.isNotEmpty && buf.isNotEmpty) out[key] = buf;
          }
          return out;
        }
      }
      final out = <String, List<String>>{};
      for (final entry in root.entries) {
        final key = entry.key;
        final v = entry.value;
        if (key is! String) continue;
        if (v is List) {
          out[key] = v.map((e) => e.toString()).toList(growable: false);
        } else if (v is String) {
          out[key] = <String>[v];
        }
      }
      return out;
    }
    return <String, List<String>>{};
  }

  Future<void> _initIndex() async {
    try {
      final enRaw = await rootBundle.loadString('assets/emoji/annotations_en.json');
      final ruRaw = await rootBundle.loadString('assets/emoji/annotations_ru.json');

      final enAnn = _extractAnnMap(jsonDecode(enRaw));
      final ruAnn = _extractAnnMap(jsonDecode(ruRaw));

      _index.clear();

      void addFrom(Map<String, List<String>> src, String emoji, List<String> buf) {
        final base = _baseEmoji(emoji);
        final variants = <String>{
          emoji,
          emoji.replaceAll('\uFE0F', '').replaceAll('\uFE0E', ''),
          base,
          base.replaceAll('\uFE0F', '').replaceAll('\uFE0E', ''),
        };
        for (final key in variants) {
          final list = src[key];
          if (list != null && list.isNotEmpty) {
            buf.addAll(list);
            break;
          }
        }
      }

      // In emoji_picker_flutter 4.4.0 defaultEmojiSet is List<CategoryEmoji>
      for (final cat in defaultEmojiSet) {
        for (final e in cat.emoji) {
          final buf = <String>[];
          addFrom(enAnn, e.emoji, buf);
          addFrom(ruAnn, e.emoji, buf);
          buf.add(e.name); // keep package english name too

          final norm = _norm(buf.join(' '));
          if (norm.isNotEmpty) {
            _index[_baseEmoji(e.emoji)] = norm;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _indexReady = true;
        _indexErr = null;
        _enCount = enAnn.length;
        _ruCount = ruAnn.length;
      });
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Emoji index init failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _indexReady = false;
        _indexErr = e.toString();
        _enCount = 0;
        _ruCount = 0;
      });
    }
  }

  List<String> _categoriesOrder() =>
      defaultEmojiSet.map((c) => c.category.name).toList(growable: false);

  String _titleFor(String name) {
    final n = name.trim().toUpperCase();
    switch (n) {
      case 'SMILEYS':
      case 'SMILEY':
      case 'PEOPLE':
        return 'Улыбки';
      case 'ANIMALS':
      case 'NATURE':
        return 'Животные';
      case 'FOODS':
      case 'FOOD':
        return 'Еда';
      case 'ACTIVITIES':
      case 'ACTIVITY':
        return 'Активность';
      case 'PLACES':
      case 'TRAVEL':
        return 'Места';
      case 'OBJECTS':
        return 'Предметы';
      case 'SYMBOLS':
        return 'Символы';
      case 'FLAGS':
        return 'Флаги';
      default:
        // Try to show something readable.
        if (n.isEmpty) return '';
        return n[0] + n.substring(1).toLowerCase();
    }
  }

  }

  IconData _iconFor(String name) {
    switch (name) {
      case 'SMILEYS':
        return Icons.emoji_emotions_outlined;
      case 'ANIMALS':
        return Icons.pets_outlined;
      case 'FOODS':
        return Icons.restaurant_outlined;
      case 'ACTIVITIES':
        return Icons.sports_basketball_outlined;
      case 'TRAVEL':
        return Icons.directions_car_outlined;
      case 'OBJECTS':
        return Icons.lightbulb_outline;
      case 'SYMBOLS':
        return Icons.alternate_email;
      case 'FLAGS':
        return Icons.flag_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  void _pick(Emoji e) {
    widget.onEmojiSelected(e);
    setState(() {
      _recents.removeWhere((x) => x.emoji == e.emoji);
      _recents.insert(0, e);
      if (_recents.length > _recentsLimit) {
        _recents.removeRange(_recentsLimit, _recents.length);
      }
    });
  }

  Future<List<Emoji>> _search(String q) async {
    final query = _norm(q);
    if (query.isEmpty) return const <Emoji>[];
    if (!_indexReady) return const <Emoji>[]; // no fallback

    final terms = query.split(' ').where((x) => x.isNotEmpty).toList(growable: false);
    if (terms.isEmpty) return const <Emoji>[];

    final res = <Emoji>[];
    for (final cat in defaultEmojiSet) {
      for (final e in cat.emoji) {
        final key = _baseEmoji(e.emoji);
        final hay = _index[key] ?? '';
        if (hay.isEmpty) continue;
        bool ok = true;
        for (final t in terms) {
          if (!hay.contains(t)) {
            ok = false;
            break;
          }
        }
        if (ok) res.add(e);
      }
    }
    return res;
  }

  Widget _emojiGrid(List<Emoji> emojis) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: emojis.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        crossAxisSpacing: _hSpace,
        mainAxisSpacing: _vSpace,
      ),
      itemBuilder: (context, i) {
        final e = emojis[i];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _pick(e),
          child: Center(
            child: Text(
              e.emoji,
              style: widget.emojiTextStyle ?? const TextStyle(fontSize: _emojiFontSize),
            ),
          ),
        );
      },
    );
  }

  Widget _recentsBlock(Color onSurface) {
    final items = _recents.take(_recentsLimit).toList(growable: true);
    if (items.isEmpty) {
      // show first row from default set
      final flat = defaultEmojiSet.expand((c) => c.emoji);
      items.addAll(flat.take(_columns));
    }

    return Column(
      key: _sectionKeys.putIfAbsent('__RECENT__', () => GlobalKey()),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
          child: Text('Часто используемые',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: onSurface)),
        ),
        _emojiGrid(items),
        Divider(height: 1, thickness: 1, color: Theme.of(context).dividerColor),
      ],
    );
  }

  Widget _normalList(Color onSurface) {
    final order = _categoriesOrder();
    for (final name in order) {
      _sectionKeys.putIfAbsent(name, () => GlobalKey());
    }

    final children = <Widget>[];

    for (final name in order) {
      final cat = defaultEmojiSet.firstWhere((c) => c.category.name == name);
      children.add(
        Column(
          key: _sectionKeys[name],
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
              child: Text(_titleFor(name),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: onSurface)),
            ),
            _emojiGrid(cat.emoji),
          ],
        ),
      );
    }

    return ListView(controller: _scroll, children: children);
  }

  Widget _searchResults(Color onSurface) {
    final q = _searchCtrl.text.trim();

    if (q.isEmpty) {
      final items = _recents.isEmpty
          ? defaultEmojiSet.expand((c) => c.emoji).take(_columns).toList()
          : _recents.take(_columns).toList();
      return ListView(
        controller: _scroll,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
            child: Text('Часто используемые',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: onSurface)),
          ),
          _emojiGrid(items),
        ],
      );
    }

    final fut = _searchFuture ??= _search(q);
    return FutureBuilder<List<Emoji>>(
      future: fut,
      builder: (context, snap) {
        final list = snap.data ?? const <Emoji>[];
        return ListView(
          controller: _scroll,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
              child: Text('Результаты',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: onSurface)),
            ),
            if (kDebugMode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Text(
                  _indexReady
                      ? 'index en=$_enCount ru=$_ruCount'
                      : 'index loading...' + (_indexErr != null ? ' err=$_indexErr' : ''),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (snap.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_indexReady ? 'Ничего не найдено' : 'Индекс не готов',
                    style: Theme.of(context).textTheme.bodyMedium),
              )
            else
              _emojiGrid(list),
          ],
        );
      },
    );
  }

  Future<void> _scrollTo(String name) async {
    final key = _sectionKeys[name];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Widget _bottomCategories(Color surface, Color primary) {
    final order = _categoriesOrder();
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final name in order)
            IconButton(
              tooltip: _titleFor(name),
              onPressed: () => _scrollTo(name),
              icon: Icon(_iconFor(name), color: primary),
            ),
        ],
      ),
    );
  }

  Widget _topRow(Color surface) {
    if (!_searchMode) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final all = _all;
          final recents = (_recents.isNotEmpty ? _recents : all).take(16).toList(growable: false);
          final perRow = ((constraints.maxWidth - 48) / 36).floor().clamp(6, 8);
          List<Widget> buildRow(int start) {
            final end = (start + perRow).clamp(0, recents.length);
            final items = recents.sublist(start, end);
            return items
                .map((e) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _selectEmoji(e),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: Center(
                            child: Text(
                              e.emoji,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList();
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: widget.searchHint,
                icon: const Icon(Icons.search),
                onPressed: () {
                  setState(() => _searchMode = true);
                  Future.microtask(() => _searchFocus.requestFocus());
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(children: buildRow(0)),
                      if (recents.length > perRow) Wrap(children: buildRow(perRow)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    // Search mode.
    return Row(
      children: [
        IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _searchMode = false;
              _query = '';
              _filtered = const [];
            });
            FocusScope.of(context).unfocus();
          },
        ),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            decoration: InputDecoration(
              hintText: widget.searchHint,
              border: InputBorder.none,
            ),
            onChanged: _onQueryChanged,
          ),
        ),
        if (_query.isNotEmpty)
          IconButton(
            tooltip: 'Очистить',
            icon: const Icon(Icons.close),
            onPressed: () {
              _searchCtrl.clear();
              _onQueryChanged('');
              _searchFocus.requestFocus();
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurfaceVariant;
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Container(color: surface, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: _topRow(surface)),
        Expanded(child: _searchMode ? _searchResults(onSurface) : _normalList(onSurface)),
        if (!_searchMode) _bottomCategories(surface, primary),
      ],
    );
  }
}
