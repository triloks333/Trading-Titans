import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';

import '../../core/money.dart';
import '../../models/quote.dart';
import '../../services/market_service.dart';
import '../../services/nav_tab_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stock_action_sheet.dart';

/// Several named, coloured watchlists, each grouped into sections.
///
/// A stock lives in one list at a time (see 20261103020000_multiple_watchlists.sql),
/// and a stock with no list belongs to the first one, which is where the star
/// button and older app versions put it.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

const _palette = [
  '#3B82F6', '#10B981', '#F59E0B', '#EF4444',
  '#8B5CF6', '#EC4899', '#0EA5E9', '#64748B',
];

Color _hex(String? hex) =>
    Color(int.tryParse('FF${(hex ?? '#3B82F6').substring(1)}', radix: 16) ?? 0xFF3B82F6);

class _WatchlistScreenState extends State<WatchlistScreen> {
  final _svc = SupabaseService();
  List<Map<String, dynamic>> _lists = [];
  List<Map<String, dynamic>> _items = [];
  String? _selected;
  bool _loading = true;
  Map<String, Quote> _quotes = const {};
  final Map<String, List<double>> _spark = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await _svc.getCachedWatchlistRaw();
    if (mounted && cached.isNotEmpty && _items.isEmpty) {
      setState(() {
        _items = cached;
        _loading = false;
      });
    }
    try {
      final results = await Future.wait([_svc.getWatchlists(), _svc.getWatchlistRaw()]);
      if (!mounted) return;
      setState(() {
        _lists = results[0];
        _items = results[1];
        if (!_lists.any((l) => l['id'] == _selected)) {
          _selected = _lists.isEmpty ? null : _lists.first['id'] as String;
        }
        _loading = false;
      });
      _refreshPrices();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _tell('Could not load watchlists.');
      }
    }
  }

  void _tell(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  /// Items in [listId]; unassigned rows count as the first list's.
  List<Map<String, dynamic>> _itemsIn(String? listId) {
    final firstId = _lists.isEmpty ? null : _lists.first['id'];
    return _items.where((i) {
      final owner = i['watchlist_id'] ?? firstId;
      return owner == listId;
    }).toList();
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) _tell(failure);
    }
  }

  // ── Lists ────────────────────────────────────────────────────────────────

  Future<void> _editList([Map<String, dynamic>? list]) async {
    final name = TextEditingController(text: list?['name'] as String? ?? '');
    var colour = list?['color'] as String? ?? _palette[_lists.length % _palette.length];

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, MediaQuery.of(sheet).viewInsets.bottom + AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(list == null ? 'New watchlist' : 'Edit watchlist',
                  style: GoogleFonts.ibmPlexSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: name,
                autofocus: list == null,
                maxLength: 30,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Long-term, Intraday'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Colour', style: GoogleFonts.ibmPlexSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink2)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _palette)
                    Semantics(
                      button: true,
                      selected: c == colour,
                      label: 'Colour $c',
                      child: GestureDetector(
                        onTap: () => setSheet(() => colour = c),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _hex(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c == colour ? AppColors.ink : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: c == colour ? const Icon(Icons.check, color: Colors.white) : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  if (list != null && _lists.length > 1)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(sheet, 'delete'),
                      icon: Icon(Icons.delete_outline, color: AppColors.bear),
                      label: Text('Delete', style: TextStyle(color: AppColors.bear)),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      if (name.text.trim().isEmpty) return;
                      Navigator.pop(sheet, 'save');
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (action == 'save') {
      await _run(
        () => _svc.saveWatchlist(id: list?['id'] as String?, name: name.text.trim(), color: colour),
        'Could not save the watchlist.',
      );
    } else if (action == 'delete' && list != null) {
      final count = _itemsIn(list['id'] as String).length;
      if (!mounted) return;
      final sure = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Delete "${list['name']}"?'),
          content: Text(count == 0
              ? 'This list is empty.'
              : 'Its $count ${count == 1 ? 'stock' : 'stocks'} will be removed from your watchlists.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text('Delete', style: TextStyle(color: AppColors.bear)),
            ),
          ],
        ),
      );
      if (sure == true) {
        await _run(() => _svc.deleteWatchlist(list['id'] as String), 'Could not delete the watchlist.');
      }
    }
  }

  // ── Items ────────────────────────────────────────────────────────────────

  Future<void> _itemMenu(Map<String, dynamic> item) async {
    final symbol = item['symbol'] as String? ?? '';
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.pureWhite,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(symbol, style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.segment_rounded),
              title: const Text('Move to section'),
              onTap: () => Navigator.pop(sheet, 'section'),
            ),
            if (_lists.length > 1)
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text('Move to another list'),
                onTap: () => Navigator.pop(sheet, 'list'),
              ),
            ListTile(
              leading: Icon(Icons.star_outline_rounded, color: AppColors.bear),
              title: Text('Remove from watchlist', style: TextStyle(color: AppColors.bear)),
              onTap: () => Navigator.pop(sheet, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    final id = item['id'] as String;
    switch (choice) {
      case 'section':
        final section = await _pickSection(item['section'] as String?);
        if (section != null) {
          await _run(() => _svc.updateWatchlistItem(id, section: section), 'Could not move it.');
        }
      case 'list':
        final target = await _pickList();
        if (target != null) {
          // A new list starts unsectioned; the old heading may not exist there.
          await _run(() => _svc.updateWatchlistItem(id, watchlistId: target, section: ''), 'Could not move it.');
        }
      case 'remove':
        await _run(
          () => _svc.removeFromWatchlist(symbol, item['market'] as String? ?? 'stock'),
          'Could not remove it.',
        );
    }
  }

  /// Returns the chosen section, '' for none, or null when cancelled.
  Future<String?> _pickSection(String? current) {
    final existing = _itemsIn(_selected)
        .map((i) => i['section'] as String?)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Move to section'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in existing)
                  ChoiceChip(
                    label: Text(s),
                    selected: s == current,
                    onSelected: (_) => Navigator.pop(d, s),
                  ),
                if (current != null)
                  ActionChip(label: const Text('No section'), onPressed: () => Navigator.pop(d, '')),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: controller,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'New section', hintText: 'e.g. Banks, IT, Pharma'),
              onSubmitted: (v) => Navigator.pop(d, v.trim().isEmpty ? null : v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(d, controller.text.trim().isEmpty ? null : controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickList() => showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.pureWhite,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final l in _lists.where((l) => l['id'] != _selected))
                ListTile(
                  leading: CircleAvatar(radius: 8, backgroundColor: _hex(l['color'] as String?)),
                  title: Text(l['name'] as String? ?? ''),
                  onTap: () => Navigator.pop(sheet, l['id'] as String),
                ),
            ],
          ),
        ),
      );

  // ── Prices ───────────────────────────────────────────────────────────────

  /// Live quotes for every row, keyed `symbol\x1Fmarket` like [MarketService.quotes].
  Future<void> _refreshPrices() async {
    final pairs = [
      for (final i in _items) (symbol: i['symbol'] as String? ?? '', market: i['market'] as String? ?? 'stock'),
    ].where((p) => p.symbol.isNotEmpty).toList();
    if (pairs.isEmpty) return;
    try {
      final fetched = await MarketService.quotes(pairs);
      if (mounted) setState(() => _quotes = {..._quotes, ...fetched});
    } catch (_) {}
    // 5-day closes, fetched once per symbol for the sparkline column.
    for (final p in pairs) {
      final key = '${p.symbol}\x1F${p.market}';
      if (_spark.containsKey(key)) continue;
      _spark[key] = const [];
      SupabaseService().getHistory(p.symbol, p.market, '5d').then((pts) {
        if (mounted) setState(() => _spark[key] = [for (final x in pts) if (x['v'] is num) (x['v'] as num).toDouble()]);
      }).catchError((_) {});
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final current = _lists.where((l) => l['id'] == _selected).firstOrNull;
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 10),
              Expanded(child: Text('Watchlists', style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink))),
              AuthIconButton(
                icon: Icons.edit_outlined,
                label: 'Edit list',
                onTap: _loading || current == null ? () {} : () => _editList(current),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: ThemeService(),
                builder: (_, _) => AuthIconButton(
                  icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  label: 'Toggle light or dark theme',
                  onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
                ),
              ),
            ]),
          ),
          if (_loading) const Expanded(child: ListSkeleton()) else ...[
            _tabs(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
              child: Row(children: [
                Text('INSTRUMENT', style: AppText.sectionLabel),
                Expanded(child: Text('5D', textAlign: TextAlign.center, style: AppText.sectionLabel)),
                Text('LTP · CHG', style: AppText.sectionLabel),
              ]),
            ),
            Expanded(child: _body()),
          ],
        ]),
      ),
    );
  }

  Widget _chip({required Widget label, required bool on, required VoidCallback onTap, VoidCallback? onLongPress}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: on ? AppColors.goldPale : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            side: BorderSide(color: on ? AppColors.goldMid : AppColors.birch),
          ),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(height: 32, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.center, child: label),
          ),
        ),
      );

  Widget _tabs() => Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 12),
          child: Row(children: [
            for (final l in _lists)
              _chip(
                on: l['id'] == _selected,
                onTap: () => setState(() => _selected = l['id'] as String),
                onLongPress: () => _editList(l),
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  // The colour dot keeps each list's identity from the old design.
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: _hex(l['color'] as String?), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${l['name']}',
                      style: AppFonts.sans(size: 13, weight: FontWeight.w500, color: l['id'] == _selected ? AppColors.goldMid : AppColors.ink3)),
                  const SizedBox(width: 6),
                  Text('${_itemsIn(l['id'] as String).length}', style: AppFonts.mono(size: 13, color: AppColors.ink4)),
                ]),
              ),
            _chip(
              on: false,
              onTap: () => _editList(),
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, size: 16, color: AppColors.ink3),
                const SizedBox(width: 4),
                Text('New list', style: AppFonts.sans(size: 13, weight: FontWeight.w500, color: AppColors.ink3)),
              ]),
            ),
          ]),
        ),
      );

  void _browse() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    NavTabService.goToTab(NavTabService.trade);
  }

  Widget _body() {
    final items = _itemsIn(_selected);
    final add = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(backgroundColor: AppColors.cream),
        onPressed: _browse,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add instrument'),
      ),
    );
    if (items.isEmpty) {
      return ListView(children: [
        SizedBox(
          height: 260,
          child: EmptyState(
            icon: Icons.star_border_rounded,
            title: 'No stocks in this list',
            message: 'Star stocks and crypto to track them here, then move them between lists.',
          ),
        ),
        add,
      ]);
    }

    // Unsectioned first, then sections A–Z.
    final groups = <String?, List<Map<String, dynamic>>>{};
    for (final i in items) {
      groups.putIfAbsent(i['section'] as String?, () => []).add(i);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => a == null ? -1 : b == null ? 1 : a.toLowerCase().compareTo(b.toLowerCase()));

    return RefreshIndicator(
      onRefresh: () async {
        await _load();
        await _refreshPrices();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          for (final key in keys) ...[
            if (key != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
                child: Text(key.toUpperCase(), style: AppText.sectionLabel),
              ),
            for (final item in groups[key]!) _tile(item),
          ],
          add,
        ],
      ),
    );
  }

  /// Exchange tag under the symbol.
  static String _exchange(String symbol, String market) => switch (market) {
        'crypto' => 'CRYPTO',
        'us_stock' => 'US',
        'pakistan_stock' => 'PSX',
        'italy_stock' => 'MIL',
        _ => RegExp(r'FUT|\d+(CE|PE)$|-(CE|PE)$').hasMatch(symbol) ? 'NFO' : 'NSE',
      };

  Widget _tile(Map<String, dynamic> item) {
    final symbol = item['symbol'] as String? ?? '';
    final market = item['market'] as String? ?? 'stock';
    final name = item['name'] as String? ?? symbol;
    final key = '$symbol\x1F$market';
    final q = _quotes[key];
    final up = (q?.changePct ?? 0) >= 0;
    final tone = up ? AppColors.bull : AppColors.bear;
    final spark = _spark[key] ?? const [];
    return InkWell(
      onTap: () => StockActionSheet.show(context, symbol: symbol, market: market, name: name, onRefresh: _load),
      onLongPress: () => _itemMenu(item),
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, 4, 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
        child: Row(children: [
          SizedBox(
            width: 112,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(symbol, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyBold),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: AppCard.badge(AppColors.cream),
                child: Text(_exchange(symbol, market), style: AppText.badge.copyWith(color: AppColors.ink3)),
              ),
            ]),
          ),
          Expanded(
            child: Semantics(
              label: '$symbol five-day trend',
              child: SizedBox(
                height: 24,
                child: spark.length < 2
                    ? null
                    : CustomPaint(painter: _Spark(spark, spark.last >= spark.first ? AppColors.bull : AppColors.bear)),
              ),
            ),
          ),
          SizedBox(
            width: 104,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(q == null ? '—' : Money.instrument(q.price, market: market),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.mono(size: 14, weight: FontWeight.w500, color: AppColors.ink)),
              Text(q == null ? ' ' : '${up ? '▲ +' : '▼ −'}${q.changePct.abs().toStringAsFixed(2)}%',
                  style: AppFonts.mono(size: 12, color: tone)),
            ]),
          ),
          IconButton(
            tooltip: 'Move or remove $symbol',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.more_vert_rounded, size: 18, color: AppColors.ink4),
            onPressed: () => _itemMenu(item),
          ),
        ]),
      ),
    );
  }
}

/// 5-day closing prices as a thin line, scaled to its own range.
class _Spark extends CustomPainter {
  _Spark(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce((a, b) => a < b ? a : b), hi = values.reduce((a, b) => a > b ? a : b);
    final span = hi == lo ? 1.0 : hi - lo;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(size.width * i / (values.length - 1), 2 + (size.height - 4) * (1 - (values[i] - lo) / span));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(_Spark old) => old.values != values || old.color != color;
}
