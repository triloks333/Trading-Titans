import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/countries.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';

/// Aggregate user counts: where people are and what they run the app on.
///
/// Renders whatever `admin_user_stats()` returns, grouped by its `dimension`
/// column. Deliberately does not enumerate the dimensions — a breakdown added
/// server-side appears here on its own, using its raw name as the heading, rather
/// than waiting for a client release to become visible. That is the whole reason
/// the RPC returns long `(dimension, value, users)` rows instead of a wide one.
///
/// Admin-only, but the gate that matters is inside the RPC: it raises for a
/// non-admin caller. Hiding the menu entry is presentation, not access control.
class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key, this.embedded = false});

  /// Body only, for the Admin panel tab.
  final bool embedded;

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  /// Headings for the dimensions we know about today. A dimension missing from
  /// here still renders, titled from its own name.
  static const _titles = {
    'total': 'All users',
    'platform': 'By platform',
    'residency': 'By billing residency',
    'country': 'By country',
    'state': 'By state',
  };

  /// Reading order. Anything unrecognised sorts to the end rather than being
  /// dropped.
  static const _order = ['total', 'platform', 'residency', 'country', 'state'];

  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await SupabaseService().getAdminUserStats();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  /// Groups rows by dimension, preserving the order the RPC sorted them into
  /// (count descending within a dimension).
  Map<String, List<Map<String, dynamic>>> get _grouped {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in _rows) {
      grouped.putIfAbsent('${row['dimension']}', () => []).add(row);
    }
    return grouped;
  }

  String _title(String dimension) =>
      _titles[dimension] ?? 'By ${dimension.replaceAll('_', ' ')}';

  /// Country rows arrive as bare codes. Spell them out, since 'IN' and 'ID' are
  /// one keystroke apart and this screen is read, not queried.
  String _label(String dimension, String value) {
    if (dimension != 'country') return value;
    final name = Countries.name(value);
    return name == null ? value : '$name ($value)';
  }

  static int _count(Map<String, dynamic> row) {
    final users = row['users'];
    return users is num ? users.toInt() : int.tryParse('$users') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final dimensions = grouped.keys.toList()
      ..sort((a, b) {
        final ai = _order.indexOf(a), bi = _order.indexOf(b);
        // Unknown dimensions (-1) go last, then alphabetically among themselves.
        if (ai == -1 && bi == -1) return a.compareTo(b);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });

    final body = _body(dimensions, grouped);
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text('User Analytics',
            style: GoogleFonts.ibmPlexSans(
                fontWeight: FontWeight.bold, color: AppColors.ink)),
        backgroundColor: AppColors.parchment,
        centerTitle: false,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: body,
    );
  }

  Widget _body(List<String> dimensions, dynamic grouped) =>
      _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: dimensions.isEmpty
                  ? ListView(
                      // Still scrollable, so pull-to-refresh works from empty.
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        Text(
                          'No figures came back. This screen is admin-only — if '
                          'you are signed in as an admin and still see this, the '
                          'request failed rather than returning nothing.',
                          style: GoogleFonts.ibmPlexSans(
                              fontSize: 13,
                              color: AppColors.ink4,
                              height: 1.5),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: dimensions.length,
                      itemBuilder: (_, i) =>
                          _card(dimensions[i], grouped[dimensions[i]]!),
                    ),
            );

  Widget _card(String dimension, List<Map<String, dynamic>> rows) {
    final total = rows.fold<int>(0, (sum, r) => sum + _count(r));
    // Every dimension partitions all users, so its own sum is the denominator. A
    // single-row dimension is always 100%, and a bar saying so is just noise.
    final showShare = rows.length > 1 && total > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warmWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_title(dimension),
                  style: GoogleFonts.ibmPlexSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
              Text('$total',
                  style: GoogleFonts.ibmPlexSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink3)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final row in rows)
            _row(
              _label(dimension, '${row['value']}'),
              _count(row),
              showShare ? _count(row) / total : null,
            ),
        ],
      ),
    );
  }

  Widget _row(String label, int count, double? share) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: GoogleFonts.ibmPlexSans(
                        fontSize: 13, color: AppColors.ink2)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                share == null
                    ? '$count'
                    : '$count  ·  ${(share * 100).toStringAsFixed(share < 0.01 ? 1 : 0)}%',
                style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink3),
              ),
            ],
          ),
          if (share != null) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 3,
                backgroundColor: AppColors.sand,
                // A share, not a task in progress. Screen readers get the figure
                // from the text beside it, so this stays decorative.
                valueColor:
                    AlwaysStoppedAnimation(AppColors.imperialGold),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
