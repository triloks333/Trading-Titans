import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_constants.dart';
import '../../core/theme.dart';
import '../../widgets/empty_state.dart';
import 'chat_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/app_network_image.dart';
import '../../services/nav_tab_service.dart';
import 'stock_detail_screen.dart';
import 'subscribe_screen.dart';
import 'orders_screen.dart';
import 'refer_earn_screen.dart';
import '../../widgets/request_feature_sheet.dart';

/// Decodes a notification's `action_data`.
///
/// PostgREST returns jsonb, which the Supabase client hands over already decoded
/// most of the time and as a raw string some of the time (older cached rows, and
/// anything that round-tripped through a text column). Both shapes are tolerated
/// because getting it wrong does not throw — it silently drops the button.
Map<String, dynamic>? parseActionData(Object? raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

/// In-app routes a notification is allowed to name.
///
/// An allow-list rather than free navigation on purpose: these values arrive from
/// a database row, so anything not named here must be inert. Adding a route means
/// adding a case to [_NotificationsScreenState._openCta] as well — a route listed
/// here with no case would render a button that silently does nothing.
///
/// Keep in step with `kAdminCtaDestinations` in admin_reward_screen.dart, which is
/// what an admin actually picks from.
const Set<String> kNotificationCtaRoutes = {
  'plans', 'topup', 'subscribe', 'wallet', 'league', 'leaderboard',
  'feature', 'wishlist', 'portfolio', 'orders', 'referral',
  'trade', 'notifications', 'chat', 'blog',
};

/// The call-to-action button's text, or null when there should be no button.
///
/// Returns null unless there is BOTH a label and somewhere real to send the user:
/// a route this build understands, or an https URL. A label on its own would
/// render a button that does nothing, and an unrecognised route is exactly what a
/// notification written for a newer app version looks like on an older one.
///
/// The https check is a trust boundary, not tidiness. These rows are written
/// server-side, so a bad or malicious `cta_url` must not be able to hand an
/// arbitrary scheme (tel:, intent:, javascript:) to the platform launcher.
String? ctaLabel(Map<String, dynamic>? data) {
  final label = (data?['cta_label'] as String?)?.trim();
  if (label == null || label.isEmpty) return null;

  final route = (data?['cta_route'] as String?)?.trim().toLowerCase() ?? '';
  if (kNotificationCtaRoutes.contains(route)) return label;

  final url = (data?['cta_url'] as String?)?.trim() ?? '';
  return url.startsWith('https://') ? label : null;
}

/// The instrument a tapped notification should open, or null when it should open
/// the detail sheet instead.
///
/// Top-level, and keyed on the SYMBOL rather than the action type, because the
/// inline version of this decision had a hole: it opened the stock screen for
/// `action_type` 'order'/'order_pending' whenever `action_data` was non-null, and
/// when that payload carried no `symbol` it did nothing whatsoever — no
/// navigation, no sheet, no fallback. The daily pending-order expiry cron writes
/// precisely that payload (`{"view":"orders"}`, no symbol), so those rows could
/// not be opened at all. That is the notification that "opens blank".
///
/// Returning null means "there is no instrument here", and the caller shows the
/// sheet — so a payload missing a field degrades to the readable view instead of
/// swallowing the tap.
String? instrumentSymbolFor(String? actionType, Map<String, dynamic>? actionData) {
  if (actionType != 'order' && actionType != 'order_pending') return null;
  final symbol = (actionData?['symbol'] as String?)?.trim();
  return (symbol == null || symbol.isEmpty) ? null : symbol;
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final rows = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _notifications = (rows as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllAsRead() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await Supabase.instance.client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', user.id)
        .eq('is_read', false);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read')),
      );
    }
  }

  /// Marks one notification read, updating the row in place.
  ///
  /// Deliberately NOT `await _load()`. Refetching set `_loading = true`, which
  /// replaced the whole list with a full-screen spinner and re-queried every row
  /// from Postgres — on every single tap, to learn one boolean the caller already
  /// knew. The tap is not awaited by the caller either, so the sheet was opening
  /// over a list that was busy rebuilding itself underneath it.
  Future<void> _markAsRead(String id) async {
    final i = _notifications.indexWhere((n) => n['id'] == id);
    if (i == -1) return;
    if (mounted) setState(() => _notifications[i]['is_read'] = true);
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true}).eq('id', id);
    } catch (_) {
      // Put the dot back rather than leave the badge claiming a row was read
      // when the database still says it was not.
      if (mounted) setState(() => _notifications[i]['is_read'] = false);
    }
  }

  int get _unreadCount =>
      _notifications.where((n) => n['is_read'] != true).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text(
                'Mark all read',
                style: GoogleFonts.ibmPlexSans(
                  color: AppColors.imperialGold,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _notifications.isEmpty
                ? const EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'You\'re all caught up',
                    message: 'Order fills, price alerts, and announcements will appear here.',
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) =>
                        _buildNotificationTile(_notifications[index]),
                  ),
      ),
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> n) {
    final isRead = n['is_read'] == true;
    final title = n['title'] as String? ?? '';
    final body = n['body'] as String? ?? '';
    final createdAt = n['created_at'] as String?;
    final id = n['id'] as String;

    Map<String, dynamic>? actionDataMap;
    final rawActionData = n['action_data'];
    if (rawActionData != null) {
      if (rawActionData is Map) {
        actionDataMap = Map<String, dynamic>.from(rawActionData);
      } else if (rawActionData is String) {
        try {
          actionDataMap = Map<String, dynamic>.from(jsonDecode(rawActionData));
        } catch (_) {}
      }
    }
    final imageUrl = actionDataMap?['image_url'] as String?;

    String timeAgo = '';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        final diff = DateTime.now().toUtc().difference(dt);
        if (diff.inMinutes < 1) {
          timeAgo = 'Just now';
        } else if (diff.inMinutes < 60) {
          timeAgo = '${diff.inMinutes}m ago';
        } else if (diff.inHours < 24) {
          timeAgo = '${diff.inHours}h ago';
        } else {
          timeAgo = '${diff.inDays}d ago';
        }
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: isRead ? AppColors.pureWhite : AppColors.goldPale,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isRead ? AppColors.birch : AppColors.goldBorder,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color:
                isRead ? AppColors.cream : AppColors.imperialGold.withAlpha(25),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _iconForTitle(title),
            size: 20,
            color: isRead ? AppColors.ink4 : AppColors.imperialGold,
          ),
        ),
        title: Text(
          title,
          style: GoogleFonts.ibmPlexSans(
            fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
            fontSize: 14,
            color: AppColors.ink,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              body,
              style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink3),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: const EdgeInsets.all(AppSpacing.md),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          InteractiveViewer(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(imageUrl, fit: BoxFit.contain),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 30),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AppNetworkImage(
                    url: imageUrl,
                    height: 150,
                    width: double.infinity,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              timeAgo,
              style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink5),
            ),
          ],
        ),
        trailing: !isRead
            ? GestureDetector(
                onTap: () => _markAsRead(id),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.imperialGold,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : null,
        onTap: () {
          if (!isRead) _markAsRead(id);
          // 'order_pending' is the pending-order alert (it carries its own
          // channel/sound); it must stay tappable like an executed 'order' one,
          // otherwise changing the type would silently drop the tap-through to
          // the stock screen. See instrumentSymbolFor for why the symbol, and
          // not the action type, is what decides this.
          final symbol =
              instrumentSymbolFor(n['action_type'] as String?, actionDataMap);
          if (symbol != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StockDetailScreen(
                  symbol: symbol,
                  market: actionDataMap?['market'] as String? ?? 'stock',
                  name: symbol,
                ),
              ),
            );
          } else {
            // Show full notification details in a premium modal bottom sheet
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: AppColors.pureWhite,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
              ),
              builder: (context) => SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.birch,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration:       BoxDecoration(
                                color: AppColors.goldPale,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.notifications_outlined, size: 16, color: AppColors.goldDeep),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              timeAgo,
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 12,
                                color: AppColors.ink4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          title,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.35,
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              body,
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 14,
                                color: AppColors.ink2,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                        if (imageUrl != null && imageUrl.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  insetPadding: const EdgeInsets.all(AppSpacing.md),
                                  child: Stack(
                                    alignment: Alignment.topRight,
                                    children: [
                                      InteractiveViewer(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.network(imageUrl, fit: BoxFit.contain),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white, size: 30),
                                        onPressed: () => Navigator.of(context).pop(),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AppNetworkImage(
                                url: imageUrl,
                                width: double.infinity,
                              ),
                            ),
                          ),
                        ],
                        // Optional call to action, carried by the notification
                        // itself rather than hardcoded per campaign: any row with
                        // action_data.cta_label plus a cta_route or cta_url gets a
                        // button here. Without this a broadcast could only ever
                        // *describe* where to go and leave the user to find it.
                        if (_ctaLabel(n) != null) ...[
                          const SizedBox(height: AppSpacing.xl),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _openCta(n);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.imperialGold,
                                foregroundColor: AppColors.pureWhite,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(
                                _ctaLabel(n)!,
                                style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ] else
                          const SizedBox(height: AppSpacing.xl),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side:       BorderSide(color: AppColors.birch),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              'Close',
                              style: GoogleFonts.ibmPlexSans(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600,
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
        },
      ),
    );
  }

  Map<String, dynamic>? _actionData(Map<String, dynamic> n) =>
      parseActionData(n['action_data']);

  String? _ctaLabel(Map<String, dynamic> n) => ctaLabel(_actionData(n));

  Future<void> _openCta(Map<String, dynamic> n) =>
      openNotificationCta(context, _actionData(n));

  IconData _iconForTitle(String title) {
    final t = title.toLowerCase();
    if (t.contains('executed') || t.contains('filled')) {
      return Icons.check_circle_outline;
    }
    if (t.contains('pending') || t.contains('placed')) {
      return Icons.schedule;
    }
    if (t.contains('cancel')) return Icons.cancel_outlined;
    return Icons.notifications_outlined;
  }
}

/// Follows a notification's call to action.
///
/// Top-level so a system-tray push tap and the in-app button land in the same
/// place through the same [kNotificationCtaRoutes] allow-list. Two copies of this
/// switch would drift, and the drift would read as a button that works inside the
/// app next to a push that goes nowhere.
///
/// `cta_route` is preferred: it stays inside the app, so the wallet and plans
/// screens open with the user's session already in hand. `cta_url` is the fallback
/// for anything that only exists on the web, and is restricted to https so a
/// crafted row cannot launch some other scheme.
///
/// [fallbackToList] is for callers that are not already showing the notification
/// list, which in practice means a push tap. It makes an absent, unrecognised or
/// 'notifications' route open the list instead of swallowing the tap — tapping a
/// notification must always do something. The in-app button leaves it false
/// because it is already on that screen.
Future<void> openNotificationCta(
  BuildContext context,
  Map<String, dynamic>? data, {
  bool fallbackToList = false,
}) async {
  final route = (data?['cta_route'] as String?)?.trim().toLowerCase();

  switch (route) {
    case 'plans':
    case 'topup':
    case 'subscribe':
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SubscribeScreen()),
      );
      return;
    case 'wallet':
      NavTabService.goToTab(NavTabService.wallet);
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    case 'league':
    case 'leaderboard':
      NavTabService.goToTab(NavTabService.league);
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    case 'feature':
      await showRequestFeatureSheet(context);
      return;
    case 'wishlist':
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChatScreen(initialTab: 2)),
      );
      return;
    case 'orders':
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OrdersScreen()),
      );
      return;
    case 'referral':
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ReferEarnScreen()),
      );
      return;
    case 'portfolio':
      NavTabService.goToTab(NavTabService.portfolio);
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    case 'trade':
      NavTabService.goToTab(NavTabService.trade);
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    case 'chat':
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChatScreen()),
      );
      return;
    case 'blog':
      // The blog is server-rendered on the marketing site, so there is nothing
      // in-app to open. Still a named route rather than leaving admins to paste a
      // URL into cta_url: the destination is fixed, and a typo in a hand-entered
      // link ships a dead button to everyone.
      await launchUrl(
        Uri.parse('${AppConstants.marketingSiteUrl}/blog'),
        mode: LaunchMode.externalApplication,
      );
      return;
    case 'notifications':
      // No navigation of its own. For the in-app button this screen already IS
      // the list, and for a push tap the fallback below opens it. The route is
      // still named here rather than dropped, because `ctaLabel` refuses to draw
      // a button for a route it does not recognise.
      break;
  }

  final raw = (data?['cta_url'] as String?)?.trim() ?? '';
  if (raw.startsWith('https://')) {
    final uri = Uri.tryParse(raw);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      } catch (_) {
        // Fall through: a launcher that refused is still a tap that deserves
        // somewhere to land.
      }
    }
  }

  if (!fallbackToList || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
  );
}
