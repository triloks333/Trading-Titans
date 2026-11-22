import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_constants.dart';
import '../../core/theme.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/empty_state.dart';
import 'chat_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/app_network_image.dart';
import '../../services/nav_tab_service.dart';
import 'stock_detail_screen.dart';
import 'subscribe_screen.dart';
import 'orders_screen.dart';
import 'coach_report_screen.dart';
import 'following_screen.dart';
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
  'trade', 'notifications', 'chat', 'blog', 'coach', 'following',
};

/// `cta_route` without case, padding or a leading slash: the chat trigger and the
/// win-back job write '/chat' and '/subscribe', which the allow-list spells bare.
String normalizedRoute(Map<String, dynamic>? data) {
  final r = (data?['cta_route'] as String?)?.trim().toLowerCase() ?? '';
  return r.startsWith('/') ? r.substring(1) : r;
}

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

  if (kNotificationCtaRoutes.contains(normalizedRoute(data))) return label;

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
  if (actionType != 'order' && actionType != 'order_pending' && actionType != 'price_alert') return null;
  final symbol = (actionData?['symbol'] as String?)?.trim();
  return (symbol == null || symbol.isEmpty) ? null : symbol;
}

/// The filter tabs, in design order. [all] is not a category of its own.
enum NoticeKind { all, diwali, chat, price, orders, league, rewards, news, other }

const Map<NoticeKind, String> kNoticeKindLabels = {
  NoticeKind.all: 'All', NoticeKind.diwali: 'Diwali', NoticeKind.chat: 'Chat', NoticeKind.price: 'Price',
  NoticeKind.orders: 'Orders', NoticeKind.league: 'League', NoticeKind.rewards: 'Rewards', NoticeKind.news: 'News',
};

/// Which tab a notification row belongs to, from what the backend actually writes:
/// `chat` (Titans Room trigger), `price_alert`, `order` / `order_pending` /
/// `expiry` / `audit_hold`, `reward` / `guest_upgrade`, and admin `broadcast` /
/// `custom` rows, which are sorted by where their button points or what they say.
NoticeKind noticeKindOf(Map<String, dynamic> n) {
  final type = (n['action_type'] as String?)?.trim().toLowerCase() ?? '';
  final data = parseActionData(n['action_data']);
  final text = '${n['title'] ?? ''} ${n['body'] ?? ''}'.toLowerCase();
  if (RegExp(r'diwali|muhurat|deepavali|samvat').hasMatch(text)) return NoticeKind.diwali;
  switch (type) {
    case 'chat':
      return NoticeKind.chat;
    case 'price_alert':
      return NoticeKind.price;
    case 'order':
    case 'order_pending':
    case 'expiry':
    case 'audit_hold':
    case 'trade':
      return NoticeKind.orders;
    case 'reward':
    case 'guest_upgrade':
      return NoticeKind.rewards;
  }
  switch (normalizedRoute(data)) {
    case 'league':
    case 'leaderboard':
      return NoticeKind.league;
    case 'blog':
      return NoticeKind.news;
    case 'chat':
    case 'wishlist':
    case 'feature':
      return NoticeKind.chat;
  }
  if (RegExp(r'\bleague\b|\brank\b|leaderboard').hasMatch(text)) return NoticeKind.league;
  if (RegExp(r'\bnews\b|\bblog\b|headline').hasMatch(text)) return NoticeKind.news;
  if (RegExp(r'reward|challenge|bonus|cash added').hasMatch(text)) return NoticeKind.rewards;
  return NoticeKind.other;
}

/// "Just now", "5m ago", "3h ago", "Yesterday", "3 days ago".
String noticeAge(String? createdAt, {DateTime? now}) {
  final dt = DateTime.tryParse(createdAt ?? '');
  if (dt == null) return '';
  final d = (now ?? DateTime.now()).toUtc().difference(dt.toUtc());
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'Yesterday';
  return '${d.inDays} days ago';
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  NoticeKind _filter = NoticeKind.all;

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
        setState(() => _notifications = (rows as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Optimistic: dots clear at once, and come back if the write fails.
  Future<void> _markAllAsRead() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final unread = _notifications.where((n) => n['is_read'] != true).toList();
    setState(() {
      for (final n in unread) {
        n['is_read'] = true;
      }
    });
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', user.id)
          .eq('is_read', false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All notifications marked as read')));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        for (final n in unread) {
          n['is_read'] = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not mark as read. Try again.')));
    }
  }

  /// Marks one notification read in place (no full refetch), restoring the dot if
  /// the database write fails.
  Future<void> _markAsRead(String id) async {
    final i = _notifications.indexWhere((n) => n['id'] == id);
    if (i == -1) return;
    if (mounted) setState(() => _notifications[i]['is_read'] = true);
    try {
      await Supabase.instance.client.from('notifications').update({'is_read': true}).eq('id', id);
    } catch (_) {
      if (mounted) setState(() => _notifications[i]['is_read'] = false);
    }
  }

  int get _unreadCount => _notifications.where((n) => n['is_read'] != true).length;

  @override
  Widget build(BuildContext context) {
    final visible = _filter == NoticeKind.all
        ? _notifications
        : _notifications.where((n) => noticeKindOf(n) == _filter).toList();
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              if (Navigator.of(context).canPop()) ...[
                AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text('Notifications', style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink)),
              ),
              OutlinedButton(
                onPressed: _unreadCount == 0 ? null : _markAllAsRead,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  foregroundColor: AppColors.ink3,
                  side: BorderSide(color: AppColors.birch),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  textStyle: AppFonts.sans(size: 13, weight: FontWeight.w500),
                ),
                child: const Text('Mark all read'),
              ),
              const SizedBox(width: 10),
              ListenableBuilder(
                listenable: ThemeService(),
                builder: (_, _) => AuthIconButton(
                  icon: AppColors.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  label: 'Toggle light or dark theme',
                  onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
                ),
              ),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 12),
            child: Row(
              children: [
                for (final e in kNoticeKindLabels.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _filter == e.key,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      labelStyle: AppFonts.sans(
                          size: 13, weight: FontWeight.w500, color: _filter == e.key ? AppColors.goldMid : AppColors.ink3),
                      side: BorderSide(color: _filter == e.key ? AppColors.goldMid : AppColors.birch),
                      onSelected: (_) => setState(() => _filter = e.key),
                    ),
                  ),
              ],
            ),
          ),
          Divider(color: AppColors.birch),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 80),
                          EmptyState(
                            icon: Icons.notifications_none_rounded,
                            title: _filter == NoticeKind.all
                                ? "You're all caught up"
                                : 'No ${kNoticeKindLabels[_filter]!.toLowerCase()} notifications',
                            message: 'Order fills, price alerts, chat mentions and announcements will appear here.',
                          ),
                        ])
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, i) => _tile(visible[i]),
                        ),
            ),
          ),
        ]),
      ),
    );
  }

  /// Icon and its tinted square, per category, as in the design.
  (IconData, Color fg, Color bg) _style(Map<String, dynamic> n, NoticeKind kind) {
    final text = '${n['title'] ?? ''} ${n['body'] ?? ''}'.toLowerCase();
    final data = parseActionData(n['action_data']);
    switch (kind) {
      case NoticeKind.diwali:
        return (text.contains('sale') ? Icons.card_giftcard_rounded : Icons.campaign_outlined,
            AppColors.titanGold, AppColors.titanGoldSoft);
      case NoticeKind.chat:
        return data?['is_everyone'] == true
            ? (Icons.campaign_outlined, AppColors.titanGold, AppColors.titanGoldSoft)
            : (Icons.chat_bubble_outline_rounded, AppColors.goldMid, AppColors.goldPale);
      case NoticeKind.price:
        final down = RegExp(r'fell|below|dropped|down').hasMatch(text);
        return (Icons.notifications_active_outlined, down ? AppColors.bear : AppColors.bull,
            down ? AppColors.bearLight : AppColors.bullLight);
      case NoticeKind.orders:
        if (RegExp(r'cancel|expired|rejected').hasMatch(text)) return (Icons.cancel_outlined, AppColors.ink3, AppColors.cream);
        if (text.contains('pending')) return (Icons.schedule_rounded, AppColors.goldMid, AppColors.goldPale);
        return (Icons.check_rounded, AppColors.goldMid, AppColors.goldPale);
      case NoticeKind.league:
        return (Icons.emoji_events_outlined, AppColors.titanGold, AppColors.titanGoldSoft);
      case NoticeKind.rewards:
        return (Icons.card_giftcard_rounded, AppColors.titanGold, AppColors.titanGoldSoft);
      case NoticeKind.news:
        return (Icons.article_outlined, AppColors.ink3, AppColors.cream);
      case NoticeKind.all:
      case NoticeKind.other:
        return (Icons.notifications_none_rounded, AppColors.ink3, AppColors.cream);
    }
  }

  Widget _tile(Map<String, dynamic> n) {
    final unread = n['is_read'] != true;
    final kind = noticeKindOf(n);
    final (icon, fg, bg) = _style(n, kind);
    final imageUrl = parseActionData(n['action_data'])?['image_url'] as String?;
    return Material(
      color: unread ? AppColors.pureWhite : Colors.transparent,
      child: InkWell(
        onTap: () => _open(n),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Icon(icon, size: 20, color: fg),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${n['title'] ?? ''}', style: AppFonts.sans(size: 14, weight: FontWeight.w600, color: AppColors.ink)),
                if ('${n['body'] ?? ''}'.isNotEmpty)
                  Text('${n['body']}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.sans(size: 13, color: AppColors.ink3, height: 1.35)),
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: AppNetworkImage(url: imageUrl, height: 120, width: double.infinity),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(noticeAge(n['created_at'] as String?), style: AppFonts.sans(size: 11, color: AppColors.ink4)),
              ]),
            ),
            if (unread)
              Semantics(
                label: 'Unread',
                child: Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6, left: AppSpacing.sm),
                  decoration: BoxDecoration(color: AppColors.goldMid, shape: BoxShape.circle),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  /// Tapping marks the row read, then goes where it points: the instrument for
  /// order and price alerts, the Orders list for an expired order, Titans Room for
  /// chat. Everything else (announcements, rewards, settlements) opens the detail
  /// sheet, which carries the campaign's own button.
  void _open(Map<String, dynamic> n) {
    if (n['is_read'] != true) _markAsRead(n['id'] as String);
    final data = _actionData(n);
    final type = n['action_type'] as String?;
    final symbol = instrumentSymbolFor(type, data);
    Widget? screen;
    if (symbol != null) {
      screen = StockDetailScreen(symbol: symbol, market: data?['market'] as String? ?? 'stock', name: symbol);
    } else if (data?['view'] == 'orders') {
      screen = const OrdersScreen();
    } else if (type == 'chat') {
      screen = const ChatScreen();
    }
    if (screen != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));
    } else {
      _showDetail(n);
    }
  }

  void _showDetail(Map<String, dynamic> n) {
    final kind = noticeKindOf(n);
    final (icon, fg, bg) = _style(n, kind);
    final imageUrl = _actionData(n)?['image_url'] as String?;
    final cta = _ctaLabel(n);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Icon(icon, size: 18, color: fg),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (kind != NoticeKind.other) ...[
                Text(kNoticeKindLabels[kind]!.toUpperCase(), style: AppText.sectionLabel),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(noticeAge(n['created_at'] as String?), style: AppText.bodySmall),
            ]),
            const SizedBox(height: AppSpacing.md),
            Text('${n['title'] ?? ''}', style: AppFonts.sans(size: 18, weight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.35),
              child: SingleChildScrollView(
                child: Text('${n['body'] ?? ''}', style: AppFonts.sans(size: 14, color: AppColors.ink2, height: 1.5)),
              ),
            ),
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              GestureDetector(
                onTap: () => showDialog(
                  context: sheet,
                  builder: (d) => Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.all(AppSpacing.md),
                    child: Stack(alignment: Alignment.topRight, children: [
                      InteractiveViewer(
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            child: Image.network(imageUrl, fit: BoxFit.contain)),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close, color: Colors.white, size: 30),
                        onPressed: () => Navigator.of(d).pop(),
                      ),
                    ]),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: AppNetworkImage(url: imageUrl, width: double.infinity),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            // The notification's own call to action (cta_label + an allow-listed
            // cta_route or an https cta_url), so a broadcast can send people somewhere.
            if (cta != null) ...[
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(sheet);
                  _openCta(n);
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: Text(cta),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            OutlinedButton(
              onPressed: () => Navigator.pop(sheet),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Close'),
            ),
          ]),
        ),
      ),
    );
  }

  Map<String, dynamic>? _actionData(Map<String, dynamic> n) => parseActionData(n['action_data']);

  String? _ctaLabel(Map<String, dynamic> n) => ctaLabel(_actionData(n));

  Future<void> _openCta(Map<String, dynamic> n) => openNotificationCta(context, _actionData(n));
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
  switch (normalizedRoute(data)) {
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
    case 'coach':
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CoachReportScreen()),
      );
      return;
    case 'following':
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FollowingScreen()),
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
