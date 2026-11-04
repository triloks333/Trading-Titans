import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../core/legal.dart';
import '../../widgets/legal_sheet.dart';
import '../../core/money.dart';
import '../../core/app_constants.dart';
import '../../services/auth_service.dart';
import '../../services/theme_service.dart';
import '../../services/tour_service.dart';
import '../../services/app_flags_service.dart';
import '../../services/plan_service.dart';
import '../../services/currency_service.dart';
import '../../core/countries.dart';
import '../../core/currency.dart';
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
import 'admin_analytics_screen.dart';
import 'admin_blog_screen.dart';
import 'admin_reward_screen.dart';

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
      safe(api.getLeaderboard()),
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
      final mine = board?.indexWhere((r) => r['is_self'] == true) ?? -1;
      _rank = mine >= 0 ? mine + 1 : null;
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
                      _stat('Trading from', _locationSummary(currency), mono: false,
                          onTap: () => _showLocationSelector(context)),
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
                    onTap: () => _openSettings(context)),
              ]),
              if (user?.isAdmin == true)
                _group('Admin', gold: true, [
                  _row(Icons.admin_panel_settings_outlined, 'Admin panel', color: AppColors.titanGold,
                      badge: _tag('ADMIN ONLY', gold: true), onTap: () => _open(const AdminRewardScreen())),
                  _row(Icons.insights_outlined, 'User analytics', color: AppColors.titanGold,
                      onTap: () => _open(const AdminAnalyticsScreen())),
                  _row(Icons.newspaper_outlined, 'Post market news & blogs', color: AppColors.titanGold,
                      onTap: () => _open(const AdminBlogScreen())),
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

  Future<void> _confirmDeleteAccount(BuildContext context, AuthService auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(
          'Delete Account?',
          style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w700, color: AppColors.bear),
        ),
        content: Text(
          'Are you sure you want to permanently delete your Trading Titans account? '
          'This will immediately remove your profile, trade history, demo cash, and rankings. '
          'This action is irreversible.',
          style: GoogleFonts.ibmPlexSans(fontSize: 13, color: AppColors.ink3, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.ibmPlexSans(color: AppColors.ink4, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.bear,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            child: Text('Delete Permanently', style: GoogleFonts.ibmPlexSans(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleting account...')),
        );
        await auth.deleteAccount();
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^(Exception|_Exception):\s*'), ''))),
        );
      }
    }
  }

  Future<void> _replayTour(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pending_tour_replay', true);
    TourService.requestReplay();
    messenger.showSnackBar(
      const SnackBar(content: Text('Starting the app tour…')),
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

  /// Every preference in one place. Selectors run on the Profile context so
  /// their sheets and dialogs open above this page.
  void _openSettings(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('Settings', style: AppText.cardTitle)),
          body: ListenableBuilder(
            listenable: ThemeService(),
            builder: (ctx, _) {
              final currency = ctx.watch<CurrencyService>();
              final auth = ctx.read<AuthService>();
              const modes = {ThemeMode.dark: 'Dark', ThemeMode.light: 'Light', ThemeMode.system: 'System default'};
              return ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: [
                _group('Appearance', [
                  // Inline theme switch: one tap, no sheet.
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: AppColors.goldPale,
                        selectedForegroundColor: AppColors.goldMid,
                        side: BorderSide(color: AppColors.birch),
                        textStyle: AppFonts.sans(size: 13, weight: FontWeight.w600),
                      ),
                      segments: [
                        for (final m in const [ThemeMode.system, ThemeMode.light, ThemeMode.dark])
                          ButtonSegment(value: m, label: Text(modes[m]!.split(' ').first)),
                      ],
                      selected: {ThemeService().themeMode},
                      onSelectionChanged: (sel) => ThemeService().setThemeMode(sel.first),
                    ),
                  ),
                  _row(Icons.currency_exchange_outlined, 'Display currency',
                      subtitle: currency.displayCurrency.label, onTap: () => _showCurrencySelector(context)),
                ]),
                _group('Trading', [
                  _row(Icons.tune_outlined, 'Preferred markets',
                      subtitle: _marketsSummary(currency.preferredMarkets), onTap: () => _showMarketsSelector(context)),
                  _row(Icons.public_outlined, 'Trading from',
                      subtitle: _locationSummary(currency), onTap: () => _showLocationSelector(context)),
                ]),
                _group('Notifications', [
                  _row(Icons.notifications_outlined, 'All notifications', onTap: () => _open(const NotificationsScreen())),
                  _row(Icons.forum_outlined, 'Titans Room chat',
                      subtitle: '@everyone and @mentions always notify', onTap: () => _open(const ChatScreen())),
                ]),
                _group('Help & about', [
                  _row(Icons.replay_circle_filled_outlined, 'Replay app tour', onTap: () => _replayTour(context)),
                  _row(Icons.privacy_tip_outlined, 'Privacy policy', onTap: () => _showPrivacyPolicy(context)),
                  _row(Icons.gavel_outlined, 'Terms & conditions', onTap: () => _showTerms(context)),
                ]),
                _group('Account', [
                  _row(Icons.delete_outline_rounded, 'Delete account',
                      subtitle: 'Permanently removes all data', color: AppColors.bear,
                      onTap: () => _confirmDeleteAccount(context, auth)),
                ]),
                Center(child: Text('Trading Titans v1.2 · Kashivwealth Management LLP', style: AppText.bodySmall)),
              ]);
            },
          ),
        ),
      ));

  void _showPrivacyPolicy(BuildContext context) =>
      showLegalSheet(context, LegalDocs.privacy);

  void _showTerms(BuildContext context) =>
      showLegalSheet(context, LegalDocs.terms);


  /// Human-readable summary of the preferred-market selection, for the row
  /// subtitle.
  static String _marketsSummary(List<String> markets) {
    const names = {
      'stock': 'Indian Stocks',
      'us_stock': 'US Stocks',
      'crypto': 'Crypto',
      'pakistan_stock': 'Pakistan Stocks',
      'italy_stock': 'Italy Stocks',
    };
    final ordered = MarketTabOrder.canonical
        .where(markets.contains)
        .map((m) => names[m] ?? m)
        .toList();
    if (ordered.isEmpty) return 'None selected';
    if (ordered.length >= 5) return 'All markets';
    return ordered.join(', ');
  }

  void _showCurrencySelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) {
        final currency = context.watch<CurrencyService>();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                Text('Display Currency',
                    style: GoogleFonts.ibmPlexSans(
                        fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink)),
                const SizedBox(height: 4),
                Text(
                  'Changes every price, balance and profit figure in the app. '
                  'Your wallet is still held in rupees.',
                  style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink4, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final c in Currency.values)
                  _themeOption(
                    context,
                    icon: switch (c) {
                      Currency.inr => Icons.currency_rupee,
                      Currency.usd => Icons.attach_money,
                      Currency.eur => Icons.euro,
                      Currency.pkr => Icons.currency_rupee,
                    },
                    title: c.label,
                    isSelected: currency.displayCurrency == c,
                    onTap: () async {
                      Navigator.pop(context);
                      await CurrencyService.instance.setDisplayCurrency(c);
                    },
                  ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Row subtitle: the most specific answer on file. Falls back to the coarse
  /// india/outside_india label for accounts that answered before the country
  /// question existed, so those users see something truthful rather than
  /// 'Not set'.
  static String _locationSummary(CurrencyService currency) {
    final country = Countries.name(currency.countryCode);
    if (country == null) return currency.location?.label ?? 'Not set';
    final state = currency.state;
    return state == null ? country : '$state, $country';
  }

  /// Country, then subdivision where we ship a list for it.
  ///
  /// Replaces the old two-option india/outside_india sheet rather than sitting
  /// beside it. Residency is derived from the country server-side now, so keeping
  /// the coarse toggle would let someone pick India and then flip the residency
  /// that decides their billing currency, leaving the two contradicting each
  /// other. One input, one answer.
  Future<void> _showLocationSelector(BuildContext context) async {
    final service = CurrencyService.instance;
    final previous = service.countryCode;
    final code = await _pickFromList(
      context,
      title: 'Trading From',
      subtitle: 'Sets the currency you are billed in: India is billed in rupees, '
          'everywhere else in dollars. It does not restrict any market.',
      options: Countries.sortedByName,
      selected: previous,
    );
    if (code == null) return;

    final states = Countries.subdivisionsOf(code);
    if (states.isEmpty) {
      // No list for this country, so anything already stored belongs to a
      // different one and must not survive the move.
      await service.setCountryAndState(code, state: '');
      return;
    }
    if (!context.mounted) return;
    final state = await _pickFromList(
      context,
      title: 'State',
      subtitle: 'Optional. Close this and only your country is saved.',
      options: [for (final s in states) MapEntry(s, s)],
      selected: service.state,
    );
    await service.setCountryAndState(
      code,
      // Dismissed: leave the state as it was, unless the country just moved, in
      // which case the old state belongs to the old country.
      state: state ?? (code == previous ? null : ''),
    );
  }

  /// A searchable single-select sheet, returning the chosen key or null if
  /// dismissed. Options are `key => label`; the label is what gets searched.
  ///
  /// The search field is not a nicety at 249 countries — scrolling that blind is
  /// how the wrong country gets saved, and the wrong country is the wrong billing
  /// currency.
  Future<String?> _pickFromList(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<MapEntry<String, String>> options,
    String? selected,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.pureWhite,
      // The list is taller than the default half-sheet, and the search field
      // needs room to sit above the keyboard.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) {
        var query = '';
        final media = MediaQuery.of(sheetContext);
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SizedBox(
            // Fixed height so the list scrolls lazily. shrinkWrap would build all
            // 249 rows on every keystroke.
            height: media.size.height * 0.75,
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                final needle = query.trim().toLowerCase();
                final shown = needle.isEmpty
                    ? options
                    : options
                        .where((e) => e.value.toLowerCase().contains(needle))
                        .toList();
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sheetHandle(),
                        Text(title,
                            style: GoogleFonts.ibmPlexSans(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.ink)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: GoogleFonts.ibmPlexSans(
                                fontSize: 12,
                                color: AppColors.ink4,
                                height: 1.4)),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          onChanged: (v) => setSheetState(() => query = v),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Search',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Expanded(
                          child: shown.isEmpty
                              ? Center(
                                  child: Text('No matches',
                                      style: GoogleFonts.ibmPlexSans(
                                          fontSize: 13,
                                          color: AppColors.ink4)),
                                )
                              : ListView.builder(
                                  itemCount: shown.length,
                                  itemBuilder: (_, i) {
                                    final option = shown[i];
                                    final isSelected =
                                        option.key == selected;
                                    return ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        option.value,
                                        style: GoogleFonts.ibmPlexSans(
                                          fontSize: 15,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      trailing: isSelected
                                          ? Icon(Icons.check,
                                              size: 18,
                                              color: AppColors.imperialGold)
                                          : null,
                                      onTap: () => Navigator.pop(
                                          context, option.key),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showMarketsSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) {
        // Local copy so toggling several markets is one save, not one per tap.
        final selected = CurrencyService.instance.preferredMarkets.toSet();
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHandle(),
                  Text('Preferred Markets',
                      style: GoogleFonts.ibmPlexSans(
                          fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  const SizedBox(height: 4),
                  Text(
                    'We open your favourite market first. You can still trade '
                    'anything, any time.',
                    style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink4, height: 1.4),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final m in const [
                    ('stock', 'Indian Stocks', Icons.currency_rupee),
                    ('us_stock', 'US Stocks', Icons.attach_money),
                    ('crypto', 'Cryptocurrency', Icons.currency_bitcoin),
                    ('pakistan_stock', 'Pakistan Stocks', Icons.account_balance_outlined),
                    ('italy_stock', 'Italy Stocks', Icons.euro),
                  ])
                    CheckboxListTile(
                      value: selected.contains(m.$1),
                      onChanged: (on) => setSheetState(() {
                        if (on == true) {
                          if (selected.length >= 3) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(
                                content: Text('You can select a maximum of 3 markets at a time.'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            return;
                          }
                          selected.add(m.$1);
                        } else if (selected.length > 1) {
                          // Never allow an empty selection: the nav bar and the
                          // default tab both need at least one market.
                          selected.remove(m.$1);
                        }
                      }),
                      activeColor: AppColors.imperialGold,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: Icon(m.$3, size: 20, color: AppColors.ink3),
                      title: Text(m.$2,
                          style: GoogleFonts.ibmPlexSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink)),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await CurrencyService.instance
                            .setPreferredMarkets(selected.toList());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.ink,
                        foregroundColor: AppColors.pureWhite,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      child: Text('Save',
                          style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sheetHandle() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.birch,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _themeOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.goldPale : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isSelected ? AppColors.goldBorder : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? AppColors.imperialGold : AppColors.ink2,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.ibmPlexSans(
                    color: isSelected ? AppColors.imperialGold : AppColors.ink,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: AppColors.imperialGold,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
