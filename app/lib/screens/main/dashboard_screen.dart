import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_constants.dart';
import '../../core/market_hours.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../models/portfolio.dart';
import '../../models/quote.dart';
import '../../services/app_flags_service.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/currency_service.dart';
import '../../services/nav_tab_service.dart';
import '../../services/plan_service.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/home_news_section.dart';
import '../../widgets/muhurat_card.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/titan_showcase.dart';
import 'analytics_screen.dart';
import 'autopsy_screen.dart';
import 'chat_screen.dart';
import 'muhurat_screen.dart' show istLabel;
import 'news_list_screen.dart';
import 'news_reader_screen.dart';
import 'notifications_screen.dart';
import 'orders_screen.dart';
import 'stock_detail_screen.dart';
import 'subscribe_screen.dart';
import 'watchlist_screen.dart';
import 'whatif_screen.dart';

/// Chart ranges on the home value card, newest-first window lengths.
const Map<String, Duration?> kHomeRanges = {
  '1D': Duration(days: 1), '1W': Duration(days: 7), '1M': Duration(days: 30), '1Y': Duration(days: 365), 'ALL': null,
};

/// Running total of realised P&L for orders filled inside [range], oldest first,
/// starting from 0. There is no stored portfolio-value history, so the home
/// chart plots what the user actually booked over the window.
List<double> realisedCurve(List<Order> orders, Duration? range, {DateTime? now}) {
  final from = range == null ? null : (now ?? DateTime.now()).subtract(range);
  final fills = orders
      .where((o) => o.realizedPnl != 0) // only executed closing orders carry realised P&L
      .map((o) => (at: o.executedAt ?? o.createdAt, pnl: o.realizedPnl))
      .where((f) => f.at != null && (from == null || f.at!.isAfter(from)))
      .toList()
    ..sort((a, b) => a.at!.compareTo(b.at!));
  var sum = 0.0;
  return [0, for (final f in fills) sum += f.pnl];
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _chatSeenKey = 'home_chat_seen_at';

  bool _loading = true;
  List<Holding> _holdings = [];
  List<Quote> _watchlist = [];
  List<Quote> _overview = [];
  List<Order> _orders = [];
  List<Map<String, dynamic>> _news = [];
  ChatMessage? _lastChat;
  int _newChats = 0;
  int _unread = 0;
  String _range = '1M';
  Timer? _pollTimer;

  final _valueKey = GlobalKey(), _actionsKey = GlobalKey(), _pulseKey = GlobalKey(), _alertsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(AppConstants.dashboardPricePoll, (_) => _refreshPrices());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPrices() async {
    try {
      final r = await Future.wait([
        SupabaseService().getMarketOverview(),
        SupabaseService().getHoldings(),
        SupabaseService().getWatchlist(),
        _loadUnread(),
      ]);
      if (mounted) {
        setState(() {
          _overview = r[0] as List<Quote>;
          _holdings = r[1] as List<Holding>;
          _watchlist = r[2] as List<Quote>;
        });
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    // Cache-first, so a returning user never waits on the network for a first paint.
    await _hydrateFromCache();
    try {
      final r = await Future.wait([
        SupabaseService().getMarketOverview(),
        SupabaseService().getHoldings(),
        SupabaseService().getWatchlist(),
        auth.refreshUser(),
        _loadUnread(),
      ]);
      if (mounted) {
        setState(() {
          _overview = r[0] as List<Quote>;
          _holdings = r[1] as List<Holding>;
          _watchlist = r[2] as List<Quote>;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
      unawaited(_maybeStartTour());
    }
    // Secondary cards load after the first paint and never block it.
    unawaited(_loadExtras());
  }

  Future<void> _hydrateFromCache() async {
    try {
      final svc = SupabaseService();
      final c = await Future.wait([svc.getCachedMarketOverview(), svc.getCachedHoldings(), svc.getCachedWatchlist()]);
      if (!mounted) return;
      final overview = c[0] as List<Quote>, holdings = c[1] as List<Holding>, watchlist = c[2] as List<Quote>;
      if (overview.isNotEmpty || holdings.isNotEmpty || watchlist.isNotEmpty) {
        setState(() {
          if (overview.isNotEmpty) _overview = overview;
          if (holdings.isNotEmpty) _holdings = holdings;
          if (watchlist.isNotEmpty) _watchlist = watchlist;
          _loading = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadExtras() async {
    final results = await Future.wait<Object?>([
      SupabaseService().getOrders(limit: 500).catchError((_) => <Order>[]),
      SupabaseService().listBlogPosts().catchError((_) => <Map<String, dynamic>>[]),
      ChatService.instance.loadRecent(),
      SharedPreferences.getInstance(),
    ]);
    if (!mounted) return;
    final chats = results[2] as List<ChatMessage>;
    final seen = DateTime.tryParse((results[3] as SharedPreferences).getString(_chatSeenKey) ?? '');
    setState(() {
      _orders = results[0] as List<Order>;
      _news = (results[1] as List<Map<String, dynamic>>).where((p) => p['published_at'] != null).toList();
      _lastChat = chats.isEmpty ? null : chats.last;
      _newChats = seen == null ? 0 : chats.where((m) => m.createdAt.isAfter(seen)).length;
    });
  }

  Future<void> _maybeStartTour() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool('dashboard_tour_seen') ?? false;
      final replay = prefs.getBool('pending_tour_replay') ?? false;
      if (seen && !replay) return;
      await prefs.setBool('dashboard_tour_seen', true);
      if (replay) await prefs.remove('pending_tour_replay');
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ShowcaseView.get().startShowCase([_alertsKey, _valueKey, _actionsKey, _pulseKey]);
      });
    } catch (_) {}
  }

  Future<void> _loadUnread() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final res = await Supabase.instance.client.from('notifications').select('id').eq('user_id', user.id).eq('is_read', false);
      if (mounted) setState(() => _unread = (res as List).length);
    } catch (_) {}
  }

  Future<void> _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _openChat() async {
    await _push(const ChatScreen());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatSeenKey, DateTime.now().toUtc().toIso8601String());
    if (mounted) setState(() => _newChats = 0);
  }

  Future<void> _openNotifications() async {
    await _push(const NotificationsScreen());
    _loadUnread();
  }

  void _openQuote(Quote q) => _push(StockDetailScreen(symbol: q.symbol, market: q.market, name: q.name));

  // Open positions only: a closed row carries today's realised P&L, not a position.
  Iterable<Holding> get _open => _holdings.where((h) => h.quantity != 0);
  double get _positions => _open.fold(0.0, (s, h) => s + h.current);
  double get _unrealised => _open.fold(0.0, (s, h) => s + h.pnl);
  double get _dayPnl => _open.fold(0.0, (s, h) => s + h.dayPnl);

  static String _money(double v) => Money.wallet(v, decimals: v.abs() < 1000 ? 2 : 0);
  static String _signed(double v) => '${v >= 0 ? '+' : '-'}${_money(v.abs())}';
  static Color _tone(num v) => v >= 0 ? AppColors.bull : AppColors.bear;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _header(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const DashboardSkeleton()
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                      children: [
                        if (_overview.isNotEmpty) _indexStrip(),
                        _valueSection(user?.walletBalance ?? 0, user?.totalRealizedPnl ?? 0),
                        _quickActions(),
                        const MuhuratCard(),
                        _roomCard(),
                        _saleCard(),
                        _watchlistSection(),
                        _newsSection(),
                      ],
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _header() {
    final nse = MarketHours.statusText(MarketHours.stock);
    final open = MarketHours.isOpen(MarketHours.stock);
    final special = MarketHours.nextSpecialSession(DateTime.now().toUtc());
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
      child: Row(children: [
        const TitanCrown(size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Trading Titans', style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: AppColors.ink, spacing: -0.2)),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '● ', style: TextStyle(color: open ? AppColors.bull : AppColors.ink4)),
                TextSpan(text: 'NSE ${open ? 'open' : nse.replaceFirst('Market ', '').toLowerCase()}'),
                if (special != null) TextSpan(text: ' · ${special.name.split(' ').first} on ${istLabel(special.start, 'EEE d MMM')}'),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.sans(size: 11, color: AppColors.ink4),
            ),
          ]),
        ),
        _badged(AuthIconButton(icon: Icons.chat_bubble_outline_rounded, label: 'Titans Room chat', onTap: _openChat),
            count: _newChats),
        const SizedBox(width: 8),
        TitanShowcase(
          showcaseKey: _alertsKey,
          title: 'Notifications',
          description: 'Order fills, price alerts and announcements land here.',
          child: _badged(AuthIconButton(icon: Icons.notifications_none_rounded, label: 'Notifications', onTap: _openNotifications),
              dot: _unread > 0),
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
    );
  }

  Widget _badged(Widget child, {int count = 0, bool dot = false}) => Stack(clipBehavior: Clip.none, children: [
        child,
        if (count > 0)
          Positioned(
            top: 4,
            right: 3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.imperialGold, borderRadius: BorderRadius.circular(8)),
              child: Text(count > 99 ? '99+' : '$count', style: AppFonts.mono(size: 10, weight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        if (dot)
          Positioned(
            top: 9,
            right: 10,
            child: Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.bear, shape: BoxShape.circle)),
          ),
      ]);

  Widget _indexStrip() => TitanShowcase(
        showcaseKey: _pulseKey,
        title: 'Market pulse',
        description: 'Live index and crypto prices. Tap one to open its chart.',
        child: Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
            child: Row(children: [
              for (final q in _overview)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _outlined(
                    onTap: () => _openQuote(q),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text((q.displayName ?? q.name).toUpperCase(), style: AppFonts.sans(size: 13, weight: FontWeight.w500, color: AppColors.ink3)),
                      const SizedBox(width: 6),
                      Text(Money.instrument(q.price, market: q.market), style: AppFonts.mono(size: 13, color: AppColors.ink)),
                      const SizedBox(width: 6),
                      Text('${q.changePct >= 0 ? '▲' : '▼'}${q.changePct.abs().toStringAsFixed(2)}%',
                          style: AppFonts.mono(size: 13, color: _tone(q.changePct))),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      );

  /// 32 dp outlined pill, the design's `.chip`.
  Widget _outlined({required Widget child, required VoidCallback onTap, bool on = false}) => Material(
        color: on ? AppColors.goldPale : Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm), side: BorderSide(color: on ? AppColors.goldMid : AppColors.birch)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(height: 32, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.center, child: child),
        ),
      );

  Widget _valueSection(double wallet, double realised) {
    final total = wallet + _positions;
    final dayBase = total - _dayPnl;
    final allTime = realised + _unrealised;
    final curve = realisedCurve(_orders, kHomeRanges[_range]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 18, AppSpacing.lg, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TitanShowcase(
          showcaseKey: _valueKey,
          title: 'Portfolio value',
          description: 'Demo cash plus the live value of your open positions, with today\'s and all-time P&L.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('TOTAL PORTFOLIO VALUE · DEMO CASH', style: AppText.sectionLabel),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(Money.wallet(total, decimals: 2), style: AppText.valueLarge),
                ),
              ),
              _planTag(),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 16, runSpacing: 2, children: [
              Text.rich(TextSpan(style: AppFonts.sans(size: 13, color: AppColors.ink4), children: [
                const TextSpan(text: 'Today '),
                TextSpan(
                    text: '${_signed(_dayPnl)} (${dayBase > 0 ? '${_dayPnl >= 0 ? '+' : ''}${(_dayPnl / dayBase * 100).toStringAsFixed(2)}' : '0.00'}%)',
                    style: AppFonts.mono(size: 13, color: _tone(_dayPnl))),
              ])),
              Text.rich(TextSpan(style: AppFonts.sans(size: 13, color: AppColors.ink4), children: [
                const TextSpan(text: 'All-time '),
                TextSpan(text: _signed(allTime), style: AppFonts.mono(size: 13, color: _tone(allTime))),
              ])),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        _chart(curve),
        const SizedBox(height: 8),
        Row(children: [
          for (final r in kHomeRanges.keys)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: r == 'ALL' ? 0 : 6),
                child: _outlined(
                  on: r == _range,
                  onTap: () => setState(() => _range = r),
                  child: Text(r, style: AppFonts.sans(size: 13, weight: FontWeight.w500, color: r == _range ? AppColors.goldMid : AppColors.ink3)),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: ElevatedButton(onPressed: () => NavTabService.goToTab(NavTabService.trade), child: const Text('Trade now')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(backgroundColor: AppColors.cream),
              onPressed: () => NavTabService.goToTab(NavTabService.wallet),
              child: const Text('Add demo cash'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _planTag() {
    final auth = context.watch<AuthService>();
    final plan = context.watch<PlanService>();
    if (!context.watch<AppFlagsService>().monetizationEnabled && !auth.isGuest) return const SizedBox.shrink();
    final label = auth.isGuest ? 'GUEST' : plan.isPaid ? plan.tier.toUpperCase() : 'FREE';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 8),
      child: InkWell(
        onTap: () => _push(const SubscribeScreen()),
        borderRadius: BorderRadius.circular(AppRadius.tag),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: AppCard.badge(AppColors.titanGoldSoft),
          child: Text(label, style: AppText.badge.copyWith(color: AppColors.titanGold)),
        ),
      ),
    );
  }

  Widget _chart(List<double> curve) {
    final last = curve.last;
    final empty = curve.length < 2;
    return Semantics(
      label: empty ? 'No closed trades in this range' : 'Realised P&L over $_range: ${_signed(last)}',
      child: SizedBox(
        height: 80,
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _SparkPainter(empty ? const [0, 0] : curve, empty ? AppColors.ink5 : _tone(last)))),
          Positioned(
            left: 0,
            top: 0,
            child: Text(empty ? 'No closed trades in $_range' : 'Realised P&L · $_range  ${_signed(last)}',
                style: AppFonts.mono(size: 11, color: AppColors.ink4)),
          ),
        ]),
      ),
    );
  }

  Widget _quickActions() {
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.search_rounded, 'Search', () => NavTabService.goToTab(NavTabService.trade)),
      (Icons.format_list_bulleted_rounded, 'Orders', () => _push(const OrdersScreen())),
      (Icons.lightbulb_outline_rounded, 'What-If', () => _push(const WhatIfScreen())),
      (Icons.manage_search_rounded, 'Autopsy', () => _push(const AutopsyScreen())),
      (Icons.show_chart_rounded, 'Analytics', () => _push(const AnalyticsScreen())),
    ];
    return TitanShowcase(
      showcaseKey: _actionsKey,
      title: 'Tools',
      description: 'Search markets, check orders, or study your trades with What-If, Autopsy and Analytics.',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, AppSpacing.lg, 14),
        child: Row(children: [
          for (final (icon, label, onTap) in actions)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: label == 'Analytics' ? 0 : 6),
                child: Material(
                  color: AppColors.pureWhite,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(children: [
                        Icon(icon, size: 20, color: AppColors.goldMid),
                        const SizedBox(height: 4),
                        Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false,
                            style: AppFonts.sans(size: 11, weight: FontWeight.w500, color: AppColors.ink)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  /// The design's `.card` row: icon, title + subtitle, trailing widget.
  Widget _cardRow({
    required Widget leading,
    required Widget title,
    required Widget subtitle,
    required Widget trailing,
    required VoidCallback onTap,
    Color? border,
    Color? fill,
    EdgeInsets margin = const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 10),
  }) =>
      Padding(
        padding: margin,
        child: Material(
          color: fill ?? AppColors.pureWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: border ?? AppColors.birch)),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                leading,
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, subtitle])),
                const SizedBox(width: 8),
                trailing,
              ]),
            ),
          ),
        ),
      );

  Widget _tag(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: AppCard.badge(bg),
        child: Text(text, style: AppText.badge.copyWith(color: fg)),
      );

  Widget _roomCard() {
    final m = _lastChat;
    final preview = m == null
        ? 'Chat, support tickets & wishlist'
        : '${m.authorName ?? 'Titan'}: ${m.body?.trim().isNotEmpty == true ? m.body!.trim() : m.kind == 'voice' ? 'Voice note' : 'Photo'}';
    return _cardRow(
      onTap: _openChat,
      leading: Stack(clipBehavior: Clip.none, children: [
        Icon(Icons.chat_bubble_outline_rounded, size: 26, color: AppColors.goldMid),
        Positioned(
          top: -2,
          right: -2,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: AppColors.bull, shape: BoxShape.circle, border: Border.all(color: AppColors.pureWhite, width: 2)),
          ),
        ),
      ]),
      title: Row(children: [
        Text('Titans Room', style: AppText.bodyBold),
        const SizedBox(width: 6),
        _tag('LIVE', AppColors.bull, AppColors.bullLight),
      ]),
      subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 12, color: AppColors.ink3)),
      trailing: _newChats > 0
          ? Container(
              constraints: const BoxConstraints(minWidth: 22),
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.imperialGold, borderRadius: BorderRadius.circular(11)),
              child: Text(_newChats > 99 ? '99+' : '$_newChats', style: AppFonts.mono(size: 11, weight: FontWeight.w600, color: Colors.white)),
            )
          : Icon(Icons.chevron_right_rounded, color: AppColors.ink4),
    );
  }

  /// Shown only while `plan_catalogue` carries sale prices; same gate as Plans.
  Widget _saleCard() {
    final plans = context.watch<PlanService>();
    if (!plans.saleActive || !context.watch<AppFlagsService>().monetizationEnabled || (!kIsWeb && Platform.isIOS)) {
      return const SizedBox.shrink();
    }
    final ends = plans.saleEndsAt;
    return _cardRow(
      onTap: () => _push(const SubscribeScreen()),
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, AppSpacing.lg, 0),
      border: AppColors.titanGold,
      fill: AppColors.titanGoldSoft,
      leading: Icon(Icons.local_fire_department_outlined, size: 28, color: AppColors.titanGold),
      title: Text('Diwali sale · 50% off every pack', style: AppText.bodyBold),
      subtitle: Text(
        'Pro, Titan & top-ups${ends == null ? '' : ' · ends ${istLabel(ends.toUtc(), 'd MMM, h:mm a')}'}',
        style: AppFonts.sans(size: 12, color: AppColors.ink3),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.ink),
    );
  }

  Widget _sectionHead(String label, String action, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 20, 4, 0),
        child: Row(children: [
          Expanded(child: Text(label.toUpperCase(), style: AppText.sectionLabel)),
          TextButton(onPressed: onTap, child: Text(action, style: AppFonts.sans(size: 13, weight: FontWeight.w500))),
        ]),
      );

  Widget _watchlistSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _sectionHead('Watchlist · Favourites', 'See all', () => _push(const WatchlistScreen())),
        Divider(color: AppColors.birch),
        if (_watchlist.isEmpty)
          ListTile(
            onTap: () => _push(const WatchlistScreen()),
            title: Text('Your watchlist is empty', style: AppText.bodyBold),
            subtitle: Text('Add stocks or coins to follow them here', style: AppText.bodySmall),
            trailing: Icon(Icons.chevron_right_rounded, color: AppColors.ink4),
          ),
        for (final q in _watchlist.take(4))
          InkWell(
            onTap: () => _openQuote(q),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(q.symbol, style: AppText.bodyBold),
                    Text('${_marketLabel(q.market)} · ${q.name}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 12, color: AppColors.ink4)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(Money.instrument(q.price, market: q.market), style: AppFonts.mono(size: 14, weight: FontWeight.w500, color: AppColors.ink)),
                  Text('${q.changePct >= 0 ? '▲ +' : '▼ −'}${q.changePct.abs().toStringAsFixed(2)}%',
                      style: AppFonts.mono(size: 12, color: _tone(q.changePct))),
                ]),
              ]),
            ),
          ),
      ]);

  static String _marketLabel(String market) => switch (market) {
        'crypto' => 'Crypto',
        'us_stock' => 'NASDAQ',
        'pakistan_stock' => 'PSX',
        'italy_stock' => 'Borsa',
        _ => 'NSE',
      };

  Widget _newsSection() {
    // Same preference filter the old carousel used: the user's markets plus global posts.
    final preferred = CurrencyService.instance.preferredMarkets;
    final mine = _news.where((p) {
      final m = parseNewsExcerpt(p['excerpt'] as String?).marketKey;
      return m == 'all' || preferred.contains(m);
    });
    final post = mine.isNotEmpty ? mine.first : (_news.isEmpty ? null : _news.first);
    if (post == null) return const SizedBox.shrink();
    final parsed = parseNewsExcerpt(post['excerpt'] as String?);
    final age = newsAge(post['published_at'] as String?);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionHead('Market news', 'More', () => _push(NewsListScreen(posts: _news))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Material(
          color: AppColors.pureWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
          child: InkWell(
            onTap: () => _push(NewsReaderScreen(post: post)),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, children: [
                  _tag((kNewsChipLabels[parsed.marketKey] ?? 'Global').toUpperCase(), AppColors.ink3, AppColors.cream),
                  if (age.isNotEmpty) _tag(age, AppColors.ink3, AppColors.cream),
                ]),
                const SizedBox(height: 6),
                Text(post['title'] as String? ?? 'Market update',
                    maxLines: 3, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 14, weight: FontWeight.w600, color: AppColors.ink, height: 1.35)),
                if (parsed.cleanExcerpt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(parsed.cleanExcerpt, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 12, color: AppColors.ink3)),
                ],
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Line plus soft fill under it, scaled to the series' own min and max.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce((a, b) => a < b ? a : b), hi = values.reduce((a, b) => a > b ? a : b);
    final span = hi - lo == 0 ? 1 : hi - lo;
    // Leave the top 18 dp for the caption.
    Offset at(int i) => Offset(size.width * i / (values.length - 1), 18 + (size.height - 22) * (1 - (values[i] - lo) / span));
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(line, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}
