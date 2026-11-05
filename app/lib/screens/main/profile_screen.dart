import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme.dart';
import '../../core/money.dart';
import '../../core/app_constants.dart';
import '../../services/auth_service.dart';
import '../../services/theme_service.dart';
import '../../services/app_flags_service.dart';
import '../../services/plan_service.dart';
import '../../services/currency_service.dart';
import '../../widgets/auth_kit.dart';
import '../../models/challenge.dart';
import '../../services/supabase_service.dart';
import 'subscribe_screen.dart';
import 'convert_account_screen.dart';
import 'challenges_screen.dart';
import 'orders_screen.dart';
import 'analytics_screen.dart';
import 'autopsy_screen.dart';
import 'glossary_screen.dart';
import 'whatif_screen.dart';
import 'watchlist_screen.dart';
import 'notifications_screen.dart';
import 'refer_earn_screen.dart';
import 'settings_screen.dart';
import 'admin_panel_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Live figures behind the header tags and row badges. Null until loaded (or if
  // a lookup fails), in which case that tag or badge is simply not shown.
  int? _level, _rank, _activeChallenges, _watchlists, _unread;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadExtras();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    }).catchError((_) {});
  }

  /// Everything optional on this screen, fetched in parallel; each piece fails alone.
  Future<void> _loadExtras() async {
    final api = SupabaseService();
    final me = api.currentUser?.id;
    Future<T?> safe<T>(Future<T> f) => f.then<T?>((v) => v).catchError((_) => null);
    final results = await Future.wait([
      safe(api.getGamificationStats()),
      safe(api.getLeagueBoard('week')),
      safe(api.getMyChallenges()),
      safe(api.getWatchlists()),
      me == null
          ? Future.value(null)
          : safe(api.client.from('notifications').select('id').eq('user_id', me).eq('is_read', false)),
    ]);
    if (!mounted) return;
    final stats = results[0] as Map<String, int>?;
    final board = results[1] as List<Map<String, dynamic>>?;
    final challenges = results[2] as List<Challenge>?;
    final lists = results[3] as List<Map<String, dynamic>>?;
    final unread = results[4] as List?;
    setState(() {
      if (stats != null) _level = TitanLevel.ladder.indexOf(TitanLevel.forXp(stats['total_xp'] ?? 0)) + 1;
      // This week's rank; null until the user has qualified.
      _rank = board?.where((r) => r['is_me'] == true).firstOrNull?['rank'] as int?;
      _activeChallenges = challenges?.where((c) => !c.isComplete).length;
      _watchlists = lists?.length;
      _unread = unread?.length;
    });
  }

  /// Pushes [screen] and refreshes the user plus the badges on return.
  Future<void> _open(Widget screen) async {
    final authService = context.read<AuthService>();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await authService.refreshUser();
    _loadExtras();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    // Hides plan badges and the top-up route while the app is free.
    final monetized = context.watch<AppFlagsService>().monetizationEnabled;
    final plan = context.watch<PlanService>();
    context.watch<ThemeService>(); // rebuild on theme change
    // Watched so money figures and the location row follow the preference.
    final currency = context.watch<CurrencyService>();
    final pnl = user?.totalRealizedPnl ?? 0;
    final planName = !monetized ? 'Free access' : (plan.isPaid ? '${plan.tier[0].toUpperCase()}${plan.tier.substring(1)} plan' : 'Free plan');

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await auth.refreshUser();
            await _loadExtras();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 18, AppSpacing.lg, AppSpacing.xl),
            children: [
              // Identity: avatar, name, email, tags; theme toggle on the right.
              Row(children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.imperialGold,
                  child: Text((user?.name ?? 'T').trim().characters.firstOrNull?.toUpperCase() ?? 'T',
                      style: AppFonts.sans(size: 22, weight: FontWeight.w700, color: Colors.white)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user?.name.isNotEmpty == true ? user!.name : 'Titan',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink)),
                    Text(
                        user == null
                            ? ''
                            : (user.email.endsWith(AppConstants.guestEmailDomain) ? 'Guest account' : user.email),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodySmall),
                    const SizedBox(height: 6),
                    // Reads the derived tier, not `profiles.subscription_active`, which
                    // defaults to true at signup and labelled free accounts "ACTIVE".
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      if (auth.isGuest) _tag('GUEST', gold: true)
                      else if (monetized && plan.isPaid) _tag(plan.tier.toUpperCase(), gold: true)
                      else _tag(monetized ? 'FREE' : 'FREE ACCESS'),
                      if (_level != null) _tag('LEVEL $_level'),
                      if (_rank != null) _tag('RANK #$_rank'),
                    ]),
                  ]),
                ),
                AuthIconButton(
                  icon: AppColors.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  label: 'Toggle light or dark theme',
                  onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
                ),
              ]),
              const SizedBox(height: AppSpacing.md),
              // 2 x 2 stats grid with hairline dividers.
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                    color: AppColors.pureWhite,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.birch)),
                child: Column(children: [
                  IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _stat('Wallet balance', Money.wallet(user?.walletBalance ?? 0)),
                      VerticalDivider(width: 1, color: AppColors.birch),
                      _stat('P&L', '${pnl >= 0 ? '+' : ''}${Money.wallet(pnl)}', color: pnl >= 0 ? AppColors.bull : AppColors.bear),
                    ]),
                  ),
                  Divider(color: AppColors.birch),
                  IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _stat('Member since', user == null ? '-' : DateFormat('MMM yyyy').format(user.createdAt.toLocal()),
                          mono: false),
                      VerticalDivider(width: 1, color: AppColors.birch),
                      _stat('Trading from', locationSummary(currency), mono: false,
                          onTap: () => _open(const PreferencesScreen())),
                    ]),
                  ),
                ]),
              ),
              if (auth.isGuest) ...[
                const SizedBox(height: AppSpacing.md),
                Material(
                  color: AppColors.titanGoldSoft,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.titanGold)),
                  child: InkWell(
                    onTap: () => _open(const ConvertAccountScreen()),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Icon(Icons.lock_open_outlined, size: 26, color: AppColors.titanGold),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Make account permanent — get ₹1,100', style: AppText.bodyBold),
                            Text('Guest account · progress is lost if you uninstall', style: AppText.bodySmall),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              ],
              _group('Account', [
                if (monetized)
                  _row(Icons.workspace_premium_outlined, 'Plans & top-ups', value: planName,
                      onTap: () => _open(const SubscribeScreen())),
                _row(Icons.track_changes_rounded, 'Challenges & rewards',
                    value: _activeChallenges == null ? null : '$_activeChallenges active', mono: true,
                    onTap: () => _open(const ChallengesScreen())),
                _row(Icons.card_giftcard_rounded, 'Refer & earn', onTap: () => _open(const ReferEarnScreen())),
              ]),
              _group('Trading', [
                _row(Icons.receipt_long_outlined, 'Order history', onTap: () => _open(const OrdersScreen())),
                _row(Icons.star_outline_rounded, 'Watchlists',
                    value: _watchlists == null ? null : '$_watchlists ${_watchlists == 1 ? 'list' : 'lists'}', mono: true,
                    onTap: () => _open(const WatchlistScreen())),
                _row(Icons.bar_chart_rounded, 'Analytics', onTap: () => _open(const AnalyticsScreen())),
                _row(Icons.medical_services_outlined, 'Trade autopsy', onTap: () => _open(const AutopsyScreen())),
                _row(Icons.lightbulb_outline_rounded, 'What-If simulator', onTap: () => _open(const WhatIfScreen())),
                _row(Icons.school_outlined, 'Trading glossary', onTap: () => _open(const GlossaryScreen())),
              ]),
              _group('More', [
                _row(Icons.forum_outlined, 'Titans Room', subtitle: 'Chat, support tickets & wishlist',
                    badge: _tag('LIVE', color: AppColors.bull, fill: AppColors.bullLight),
                    onTap: () => _open(const ChatScreen())),
                _row(Icons.notifications_outlined, 'Notifications',
                    value: (_unread ?? 0) > 0 ? '$_unread new' : null, mono: true,
                    onTap: () => _open(const NotificationsScreen())),
                _row(Icons.settings_outlined, 'Settings', subtitle: 'Theme, currency, markets, alerts, account, legal',
                    onTap: () => _open(const SettingsScreen())),
              ]),
              if (user?.isAdmin == true)
                _group('Admin', gold: true, [
                  _row(Icons.admin_panel_settings_outlined, 'Admin panel', color: AppColors.titanGold,
                      subtitle: 'Broadcast, rewards, blog and users',
                      badge: _tag('ADMIN ONLY', gold: true), onTap: () => _open(const AdminPanelScreen())),
                ]),
              _group(null, [
                _row(Icons.logout_rounded, 'Sign out', chevron: false, onTap: auth.logout),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Trading Titans${_version.isEmpty ? '' : ' v$_version'} · Kashivwealth Management LLP',
                  textAlign: TextAlign.center,
                  style: AppFonts.sans(size: 11, color: AppColors.ink4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, {bool gold = false, Color? color, Color? fill}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: AppCard.badge(fill ?? (gold ? AppColors.titanGoldSoft : AppColors.cream)),
        child: Text(text, style: AppText.badge.copyWith(color: color ?? (gold ? AppColors.titanGold : AppColors.ink3))),
      );

  Widget _stat(String label, String value, {Color? color, VoidCallback? onTap, bool mono = true}) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppFonts.sans(size: 11, color: AppColors.ink4)),
              const SizedBox(height: 2),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono
                      ? AppFonts.mono(size: 14, weight: FontWeight.w600, color: color ?? AppColors.ink)
                      : AppFonts.sans(size: 14, weight: FontWeight.w600, color: color ?? AppColors.ink)),
            ]),
          ),
        ),
      );

  /// One grouped-list row: icon, label (+ optional subtitle), then a muted value,
  /// a badge, and a chevron, as in the design.
  Widget _row(IconData icon, String label,
          {required VoidCallback onTap,
          String? subtitle,
          String? value,
          bool mono = false,
          Widget? badge,
          Color? color,
          bool chevron = true}) =>
      InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 20, color: color ?? AppColors.ink3),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: AppFonts.sans(size: 14, weight: FontWeight.w500, color: AppColors.ink)),
                  if (subtitle != null) Text(subtitle, style: AppFonts.sans(size: 12, color: AppColors.ink4)),
                ]),
              ),
              if (value != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(value, style: (mono ? AppFonts.mono : AppFonts.sans)(size: 12, color: AppColors.ink4)),
              ],
              if (badge != null) ...[const SizedBox(width: AppSpacing.sm), badge],
              if (chevron && badge == null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.ink4),
              ],
            ]),
          ),
        ),
      );

  /// A titled (or untitled) group of rows in one bordered card.
  Widget _group(String? title, List<Widget> rows, {bool gold = false}) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(title.toUpperCase(),
                  style: AppText.sectionLabel.copyWith(color: gold ? AppColors.titanGold : null)),
            ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
                color: AppColors.pureWhite,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: gold ? AppColors.titanGold : AppColors.birch)),
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[if (i > 0) Divider(color: AppColors.birch), rows[i]],
            ]),
          ),
        ]),
      );
}
