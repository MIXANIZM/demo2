import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// WhatsApp-like Emoji picker (works with emoji_picker_flutter 4.4.0):
/// - Search bar on top (real search, async in 4.4.0).
/// - One continuous vertical scroll: Recents -> Category1 -> Category2 -> ...
/// - Bottom categories act like anchors (jump to section).
/// - Dense grid (9 columns).
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
  static const int _recentsLimit = 28; // 7x4
  static const int _columns = 9;
  static const double _emojiSize = 26;
  static const double _hSpace = 6;
  static const double _vSpace = 6;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _searchMode = false;
  bool _searchIndexReady = false;
  final Map<String, String> _emojiSearchIndex = <String, String>{};

  final List<Emoji> _recents = <Emoji>[];

  late final Map<Category, GlobalKey> _sectionKeys;
  Category _activeCategory = Category.RECENT;

  // Search caching to avoid flicker while typing.
  String _lastQuery = '';
  Future<List<Emoji>>? _searchFuture;

  @override
  void initState() {
    super.initState();

    _sectionKeys = {
      Category.RECENT: GlobalKey(),
      for (final item in defaultEmojiSet) (item as dynamic).category as Category: GlobalKey(),
    };

    _scroll.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
    _initSearchIndex();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    if (q == _lastQuery) return;
    _lastQuery = q;

    if (q.isEmpty) {
      setState(() {
        _searchFuture = null;
      });
      return;
    }

    setState(() {
      // emoji_picker_flutter 4.4.0 search is async (Future<List<Emoji>>).
      _searchFuture = _searchEmojis(q);
    });
  }


  Future<void> _initSearchIndex() async {
    try {
      // Load CLDR annotations (keywords) for EN + RU to support emoji search in both languages.
      final enRaw = await rootBundle.loadString('assets/emoji/annotations_en.json');
      final ruRaw = await rootBundle.loadString('assets/emoji/annotations_ru.json');

      final enJson = jsonDecode(enRaw) as Map<String, dynamic>;
      final ruJson = jsonDecode(ruRaw) as Map<String, dynamic>;

      final enAnn = (enJson['annotations'] as Map<String, dynamic>)['annotations'] as Map<String, dynamic>;
      final ruAnn = (ruJson['annotations'] as Map<String, dynamic>)['annotations'] as Map<String, dynamic>;

      // Build a compact searchable string per emoji that includes:
      // - the emoji itself
      // - EN default/tts
      // - RU default/tts
      for (final e in defaultEmojiSet) {
        final emoji = (e as dynamic).emoji as String;
        final buf = <String>[];

        void addFrom(Map<String, dynamic> src) {
          Map? v;
          // CLDR keys sometimes omit variation selectors (FE0F/FE0E) or include/omit skin-tone modifiers.
          // Try a few normalized variants to improve match rate (RU search relies heavily on this).
          final base = _stripEmojiMods(emoji);
          final variants = <String>{
            emoji,
            emoji.replaceAll('\uFE0F', '').replaceAll('\uFE0E', ''),
            base,
            base.replaceAll('\uFE0F', '').replaceAll('\uFE0E', ''),
          };
          for (final key in variants) {
            final vv = src[key];
            if (vv is Map) { v = vv; break; }
          }
          if (v != null) {
            final def = v['default'];
            final tts = v['tts'];
            if (def is List) buf.addAll(def.cast<String>());
            if (tts is List) buf.addAll(tts.cast<String>());
          }
        }

        addFrom(enAnn);
        addFrom(ruAnn);

        final joined = _normalizeAndStem(buf.join(' '));
        _emojiSearchIndex[emoji] = joined;
      }

      if (mounted) {
        setState(() {
          _searchIndexReady = true;
        });
      }
    } catch (_) {
      // If assets are missing or parsing fails, fallback to the package search.
      if (mounted) {
        setState(() {
          _searchIndexReady = false;
        });
      }
    }
  }

  
  String _stemRu(String w) {
    // very lightweight Russian stemming for emoji search (good enough for plural/cases)
    var s = w;
    const suffixes = [
      'иями','ями','ами','его','ого','ему','ому','ыми','ими','ее','ие','ые','ое',
      'ий','ый','ая','яя','ое','ее','ов','ев','ом','ем','ах','ях','ам','ям','ою','ею',
      'а','я','ы','и','е','у','ю','о','ь'
    ];
    for (final suf in suffixes) {
      if (s.length > suf.length + 2 && s.endsWith(suf)) {
        s = s.substring(0, s.length - suf.length);
        break;
      }
    }
    return s;
  }

  String _stemEn(String w) {
    var s = w;
    const suffixes = ['ing','ed','es','s'];
    for (final suf in suffixes) {
      if (s.length > suf.length + 2 && s.endsWith(suf)) {
        s = s.substring(0, s.length - suf.length);
        break;
      }
    }
    return s;
  }

  String _normalizeAndStem(String s) {
    final norm = _normalizeForSearch(s);
    if (norm.isEmpty) return '';
    final parts = norm.split(' ').where((p) => p.isNotEmpty);
    final out = <String>[];
    for (final p in parts) {
      // keep both original token and stems for better matching
      out.add(p);
      final hasCyr = RegExp(r'[а-я]', unicode: true).hasMatch(p);
      out.add(hasCyr ? _stemRu(p) : _stemEn(p));
    }
    return out.where((e) => e.isNotEmpty).join(' ');
  }

String _normalizeForSearch(String s) {
    final lower = s.toLowerCase().replaceAll('ё', 'е');
    // keep letters/numbers/spaces; replace everything else with spaces
    return lower.replaceAll(RegExp(r'[^a-z0-9а-я\s]+', unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<List<Emoji>> _searchEmojis(String query) async {
    final qNorm = _normalizeForSearch(query);
    if (qNorm.isEmpty) return <Emoji>[];

    // If index isn't ready, fallback to emoji_picker_flutter search.
    if (!_searchIndexReady) {
      return EmojiPickerUtils().searchEmoji(query, defaultEmojiSet);
    }

    final tokensRaw = qNorm.split(' ').where((t) => t.isNotEmpty).toList(growable: false);
    if (tokensRaw.isEmpty) return <Emoji>[];

    // Add stems to query tokens as well.
    final tokens = <String>[];
    for (final t in tokensRaw) {
      tokens.add(t);
      final hasCyr = RegExp(r'[а-я]', unicode: true).hasMatch(t);
      tokens.add(hasCyr ? _stemRu(t) : _stemEn(t));
    }
    final uniqTokens = tokens.where((e) => e.isNotEmpty).toSet().toList(growable: false);

    // Score emojis by number of matched tokens (OR matching) and return best first.
    final scored = <Emoji, int>{};
    for (final e in defaultEmojiSet) {
      final emoji = (e as dynamic).emoji as String;
      final hay = _emojiSearchIndex[emoji] ?? '';
      int score = 0;
      for (final t in uniqTokens) {
        if (t.length < 2) continue;
        if (hay.contains(t)) score++;
      }
      if (score > 0) scored[e as Emoji] = score;
    }

    final list = scored.keys.toList(growable: false);
    list.sort((a, b) => (scored[b] ?? 0).compareTo(scored[a] ?? 0));
    return list;
  }

  void _onScroll() {
    if (!mounted) return;
    if (_searchCtrl.text.trim().isNotEmpty) return; // during search, no active section tracking

    Category? best;
    double bestDy = double.infinity;

    for (final entry in _sectionKeys.entries) {
      final kCtx = entry.value.currentContext;
      if (kCtx == null) continue;
      final box = kCtx.findRenderObject();
      if (box is! RenderBox) continue;

      final pos = box.localToGlobal(Offset.zero);
      final dy = pos.dy.abs();

      if (dy < bestDy) {
        bestDy = dy;
        best = entry.key;
      }
    }

    if (best != null && best != _activeCategory) {
      setState(() => _activeCategory = best!);
    }
  }

  void _jumpTo(Category c) {
    final key = _sectionKeys[c];
    final ctx = key?.currentContext;
    if (ctx == null) return;

    // Leave search mode when jumping.
    if (_searchCtrl.text.isNotEmpty) {
      _searchCtrl.clear();
      FocusScope.of(context).unfocus();
    }

    setState(() => _activeCategory = c);
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: 0.02,
    );
  }

  void _selectEmoji(Emoji e) {
    widget.onEmojiSelected(e);

    setState(() {
      _recents.removeWhere((x) => x.emoji == e.emoji);
      _recents.insert(0, e);
      if (_recents.length > _recentsLimit) {
        _recents.removeRange(_recentsLimit, _recents.length);
      }
    });
  }

  // --- Category helpers (safe for 4.4.0) ---

  List<Category> _categoryOrder() {
    final res = <Category>[Category.RECENT];
    for (final item in defaultEmojiSet) {
      final c = (item as dynamic).category as Category;
      if (!res.contains(c)) res.add(c);
    }
    return res;
  }

  List<Emoji> _emojisForDefaultItem(dynamic item) {
    // Different versions of emoji_picker_flutter used different field names.
    // We keep it runtime-safe.
    try {
      final v = item.emojis;
      if (v is List<Emoji>) return v;
    } catch (_) {}
    try {
      final v = item.emoji;
      if (v is List<Emoji>) return v;
    } catch (_) {}
    try {
      final v = item.emojiList;
      if (v is List<Emoji>) return v;
    } catch (_) {}
    return const <Emoji>[];
  }

  String _titleFor(Category c) {
    switch (c) {
      case Category.RECENT:
        return 'Недавние';
      case Category.SMILEYS:
        return 'Смайлики и люди';
      case Category.ANIMALS:
        return 'Животные и природа';
      case Category.FOODS:
        return 'Еда и напитки';
      case Category.ACTIVITIES:
        return 'Активности';
      case Category.TRAVEL:
        return 'Путешествия';
      case Category.OBJECTS:
        return 'Объекты';
      case Category.SYMBOLS:
        return 'Символы';
      case Category.FLAGS:
        return 'Флаги';
      default:
        return c.toString();
    }
  }

  IconData _iconForCategory(Category c) {
    switch (c) {
      case Category.RECENT:
        return Icons.access_time;
      case Category.SMILEYS:
        return Icons.emoji_emotions_outlined;
      case Category.ANIMALS:
        return Icons.pets_outlined;
      case Category.FOODS:
        return Icons.restaurant_menu;
      case Category.ACTIVITIES:
        return Icons.sports_esports;
      case Category.TRAVEL:
        return Icons.directions_car;
      case Category.OBJECTS:
        return Icons.lightbulb_outline;
      case Category.SYMBOLS:
        return Icons.emoji_symbols;
      case Category.FLAGS:
        return Icons.flag_outlined;
      default:
        return Icons.emoji_emotions_outlined;
    }
  }

  // --- UI blocks ---

  Widget _sectionHeader(String title, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: onSurface,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  SliverGrid _emojiGrid(List<Emoji> emojis, Color surface) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final e = emojis[i];
          return InkWell(
            onTap: () => _selectEmoji(e),
            borderRadius: BorderRadius.circular(10),
            child: Center(
              child: Text(
                e.emoji,
                style: widget.emojiTextStyle ?? const TextStyle(fontSize: _emojiSize),
              ),
            ),
          );
        },
        childCount: emojis.length,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        crossAxisSpacing: _hSpace,
        mainAxisSpacing: _vSpace,
      ),
    );
  }

  Widget _buildSearchBar(Color surface, Color onSurface) {
    return Material(
      color: surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          children: [
            if (!_searchMode)
              IconButton(
                icon: Icon(Icons.search, color: onSurface),
                tooltip: widget.searchHint,
                onPressed: () {
                  setState(() => _searchMode = true);
                  // focus after rebuild
                  Future.microtask(() => _searchFocus.requestFocus());
                },
              )
            else ...[
              IconButton(
                icon: Icon(Icons.arrow_back, color: onSurface),
                onPressed: () {
                  _searchCtrl.clear();
                  _searchFocus.unfocus();
                  setState(() => _searchMode = false);
                },
              ),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bottomCategories(Color surface, Color onSurface) {
    final primary = Theme.of(context).colorScheme.primary;
    final order = _categoryOrder();

    return Material(
      color: surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final c in order)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _jumpTo(c),
                  icon: Icon(
                    _iconForCategory(c),
                    size: 22,
                    color: (c == _activeCategory && _searchCtrl.text.isEmpty) ? primary : onSurface,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildSearchEmpty(Color surface, Color onSurface) {
    // When search is opened but query is empty: show only the first row of recents.
    final items = _recents.take(_columns).toList(growable: false);
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text('Недавние', style: TextStyle(color: onSurface, fontWeight: FontWeight.w600)),
          ),
        ),
        _emojiGrid(items, surface),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }

  Widget _buildSearchResults(Color surface, Color onSurface) {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return _buildSearchEmpty(surface, onSurface);

    final future = _searchFuture ?? _searchEmojis(q);

    return FutureBuilder<List<Emoji>>(
      future: future,
      builder: (context, snap) {
        final data = snap.data ?? const <Emoji>[];
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(
              key: _sectionKeys[Category.RECENT],
              child: _sectionHeader('Результаты', onSurface),
            ),
            _emojiGrid(data, surface),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
          ],
        );
      },
    );
  }

  Widget _buildNormalList(Color surface, Color onSurface) {
    final cats = defaultEmojiSet;

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        // Recents section
        SliverToBoxAdapter(
          key: _sectionKeys[Category.RECENT],
          child: _sectionHeader(_titleFor(Category.RECENT), onSurface),
        ),
        _emojiGrid(_recents, surface),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Divider(height: 14),
          ),
        ),

        // Categories sequentially
        for (final item in cats) ...[
          SliverToBoxAdapter(
            key: _sectionKeys[(item as dynamic).category as Category],
            child: _sectionHeader(_titleFor((item as dynamic).category as Category), onSurface),
          ),
          _emojiGrid(_emojisForDefaultItem(item), surface),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Ensure we have a bounded height; otherwise scrolling won't work.
        final maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : 360.0;
        final h = math.max(280.0, maxH);

        return SizedBox(
          height: h,
          child: Column(
            children: [
              _buildSearchBar(surface, onSurface),
              Expanded(
                child: _searchMode ? _buildSearchResults(surface, onSurface) : _buildNormalList(surface, onSurface),
              ),
              if (!_searchMode) _bottomCategories(surface, onSurface),
            ],
          ),
        );
      },
    );
  }
}
