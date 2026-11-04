import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';

import '../../widgets/stock_action_sheet.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../services/nav_tab_service.dart';

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

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Watchlists', style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.parchment,
        foregroundColor: AppColors.ink,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'New watchlist',
            icon: const Icon(Icons.add_rounded),
            onPressed: _loading ? null : () => _editList(),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const ListSkeleton()
            : Column(
                children: [
                  if (_lists.isNotEmpty) _tabs(),
                  Expanded(child: _body()),
                ],
              ),
      ),
    );
  }

  Widget _tabs() {
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 8),
        children: [
          for (final l in _lists)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onLongPress: () => _editList(l),
                child: ChoiceChip(
                  // The colour dot is the list's identity; a checkmark would cover it.
                  showCheckmark: false,
                  avatar: CircleAvatar(radius: 6, backgroundColor: _hex(l['color'] as String?)),
                  label: Text('${l['name']} · ${_itemsIn(l['id'] as String).length}'),
                  selected: l['id'] == _selected,
                  selectedColor: _hex(l['color'] as String?).withValues(alpha: 0.18),
                  onSelected: (_) => setState(() => _selected = l['id'] as String),
                ),
              ),
            ),
          if (_selected != null)
            IconButton(
              tooltip: 'Edit this watchlist',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _editList(_lists.firstWhere((l) => l['id'] == _selected)),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    final items = _itemsIn(_selected);
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.star_border_rounded,
        title: 'No stocks in this list',
        message: 'Star stocks and crypto to track them here, then move them between lists.',
        actionLabel: 'Browse stocks',
        onAction: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
          NavTabService.goToTab(NavTabService.trade);
        },
      );
    }

    // Unsectioned first, then sections A–Z.
    final groups = <String?, List<Map<String, dynamic>>>{};
    for (final i in items) {
      groups.putIfAbsent(i['section'] as String?, () => []).add(i);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => a == null ? -1 : b == null ? 1 : a.toLowerCase().compareTo(b.toLowerCase()));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        children: [
          for (final key in keys) ...[
            if (key != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
                child: Text(key.toUpperCase(), style: AppText.sectionLabel),
              ),
            for (final item in groups[key]!) ...[
              const SizedBox(height: AppSpacing.sm),
              _tile(item),
            ],
          ],
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> item) {
    final symbol = item['symbol'] as String? ?? '';
    final market = item['market'] as String? ?? 'stock';
    final name = item['name'] as String? ?? symbol;
    return GestureDetector(
      onTap: () => StockActionSheet.show(context, symbol: symbol, market: market, name: name, onRefresh: _load),
      onLongPress: () => _itemMenu(item),
      child: Container(
        padding: const EdgeInsets.only(left: AppSpacing.md),
        decoration: AppCard.secondary,
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(symbol, style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, color: AppColors.ink)),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.ibmPlexSans(color: AppColors.ink4, fontSize: 13)),
                  ],
                ),
              ),
            ),
            Text(market.toUpperCase(), style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink5)),
            IconButton(
              tooltip: 'Move or remove',
              icon: Icon(Icons.more_vert_rounded, color: AppColors.ink4),
              onPressed: () => _itemMenu(item),
            ),
          ],
        ),
      ),
    );
  }
}
