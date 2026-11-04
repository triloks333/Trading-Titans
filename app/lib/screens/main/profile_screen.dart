import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
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
import '../../widgets/crown_logo.dart';
import '../../widgets/plan_badge.dart';
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
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    // Hides plan badges and the top-up route while the app is free.
    final monetized = context.watch<AppFlagsService>().monetizationEnabled;
    final plan = context.watch<PlanService>();
    context.watch<ThemeService>(); // rebuild on theme change
    // Watched so the row subtitles and every money figure on this screen update
    // the moment the preference changes.
    context.watch<CurrencyService>();
    

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: AppCard.primary,
              child: Column(
                children: [
                  const CrownLogo(size: 56, withRing: true),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          user?.name ?? 'Titan',
                          style: GoogleFonts.ibmPlexSans(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // The plan sits next to the name, which is where a user
                      // looks for it and where it appears on the leaderboard.
                      if (monetized && plan.isPaid) ...[
                        const SizedBox(width: AppSpacing.sm),
                        PlanBadge(tier: plan.tier),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    user == null
                        ? 'you@domain.com'
                        : (user.email.endsWith(AppConstants.guestEmailDomain)
                            ? 'Guest account'
                            : user.email),
                    style: GoogleFonts.ibmPlexSans(fontSize: 14, color: AppColors.ink4),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Reads the derived tier, not `profiles.subscription_active`.
                  // That column defaults to true at signup and no payment path
                  // has ever written it, so it labelled brand-new free accounts
                  // "ACTIVE".
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                    decoration: AppCard.badge(
                        monetized && plan.isPaid ? AppColors.bullLight : AppColors.cream),
                    child: Text(
                      monetized
                          ? (plan.isPaid ? '${plan.tier.toUpperCase()} PLAN' : 'FREE PLAN')
                          : 'FREE ACCESS',
                      style: GoogleFonts.ibmPlexSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: monetized && plan.isPaid
                              ? AppColors.bull
                              : AppColors.ink4,
                          letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _detailRow('Wallet Balance', Money.wallet(user?.walletBalance ?? 0)),
                  const SizedBox(height: AppSpacing.sm),
                  _detailRow('P&L', Money.wallet(user?.totalRealizedPnl ?? 0),
                      valueColor: (user?.totalRealizedPnl ?? 0) >= 0 ? AppColors.bull : AppColors.bear),
                  const SizedBox(height: AppSpacing.sm),
                  _detailRow('Member Since', user != null ? user.createdAt.toLocal().toShortDateString() : '-'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (auth.isGuest) ...[
              ElevatedButton.icon(
                onPressed: () async {
                  final authService = context.read<AuthService>();
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ConvertAccountScreen()));
                  await authService.refreshUser();
                },
                icon: Icon(Icons.lock_open_outlined,
                    size: 18, color: AppColors.pureWhite),
                label: Text('Make account permanent \u2014 get \u20b91,100',
                    style: GoogleFonts.ibmPlexSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.pureWhite,
                        letterSpacing: 0.3)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            ElevatedButton(
              onPressed: () async {
                final authService = context.read<AuthService>();
                await Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const ChallengesScreen()));
                await authService.refreshUser();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.imperialGold,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: Text('Challenges & Rewards',
                  style: GoogleFonts.ibmPlexSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.pureWhite,
                      letterSpacing: 0.5)),
            ),
            if (monetized) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () async {
                  final authService = context.read<AuthService>();
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscribeScreen()));
                  await authService.refreshUser();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.birch),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
                child: Text('Plans & top-ups',
                    style: GoogleFonts.ibmPlexSans(
                        fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            
            
            if (auth.isGuest)
              _group('Account', [
                _row(context, Icons.lock_open_outlined, 'Make account permanent', screen: const ConvertAccountScreen()),
              ]),
            _group('Trading', [
              _row(context, Icons.star_outline_rounded, 'Watchlists', screen: const WatchlistScreen()),
              _row(context, Icons.receipt_long, 'Order history', screen: const OrdersScreen()),
              _row(context, Icons.bar_chart, 'Analytics', screen: const AnalyticsScreen()),
              _row(context, Icons.medical_services_outlined, 'Trade autopsy', screen: const AutopsyScreen()),
              _row(context, Icons.lightbulb_outline, 'What-If simulator', screen: const WhatIfScreen()),
              _row(context, Icons.school_outlined, 'Trading glossary', screen: const GlossaryScreen()),
              _row(context, Icons.card_giftcard, 'Refer & earn', screen: const ReferEarnScreen()),
            ]),
            _group('More', [
              _row(context, Icons.forum_outlined, 'Titans Room', subtitle: 'Chat, support tickets & wishlist', screen: const ChatScreen()),
              _row(context, Icons.notifications_outlined, 'Notifications', screen: const NotificationsScreen()),
              _row(context, Icons.settings_outlined, 'Settings',
                  subtitle: 'Theme, currency, markets, legal, account', onTap: () => _openSettings(context)),
            ]),
            if (user?.isAdmin == true)
              _group('Admin', [
                _row(context, Icons.admin_panel_settings_outlined, 'Admin panel', screen: const AdminRewardScreen()),
                _row(context, Icons.insights_outlined, 'User analytics', screen: const AdminAnalyticsScreen()),
                _row(context, Icons.newspaper_outlined, 'Post market news & blogs', screen: const AdminBlogScreen()),
              ]),
            OutlinedButton(
              onPressed: auth.logout,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.bear, side: BorderSide(color: AppColors.bear)),
              child: const Text('Sign out'),
            ),
            const SizedBox(height: AppSpacing.xl),
            Center(child: Text('Trading Titans v1.2', style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink5))),
          ],
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
          style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w800, color: AppColors.bear),
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
      const SnackBar(content: Text('Starting the app tourâ€¦')),
    );
  }

  /// One grouped-list row. [screen] pushes a page and refreshes the user on
  /// return; otherwise [onTap] runs.
  Widget _row(BuildContext context, IconData icon, String label,
          {Widget? screen, VoidCallback? onTap, String? subtitle, Color? color}) =>
      ListTile(
        onTap: screen == null
            ? onTap
            : () async {
                final authService = context.read<AuthService>();
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
                await authService.refreshUser();
              },
        leading: Icon(icon, size: 20, color: color ?? AppColors.ink3),
        title: Text(label, style: AppFonts.sans(size: 14, weight: FontWeight.w500, color: color ?? AppColors.ink)),
        subtitle: subtitle == null ? null : Text(subtitle, style: AppText.bodySmall),
        trailing: Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.ink4),
      );

  /// A titled group of rows in one bordered card.
  Widget _group(String title, List<Widget> rows) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
            child: Text(title.toUpperCase(), style: AppText.sectionLabel),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
                color: AppColors.pureWhite,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.birch)),
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
                  _row(ctx, Icons.palette_outlined, 'App theme',
                      subtitle: modes[ThemeService().themeMode], onTap: () => _showThemeSelector(context)),
                  _row(ctx, Icons.currency_exchange_outlined, 'Display currency',
                      subtitle: currency.displayCurrency.label, onTap: () => _showCurrencySelector(context)),
                ]),
                _group('Trading', [
                  _row(ctx, Icons.tune_outlined, 'Preferred markets',
                      subtitle: _marketsSummary(currency.preferredMarkets), onTap: () => _showMarketsSelector(context)),
                  _row(ctx, Icons.public_outlined, 'Trading from',
                      subtitle: _locationSummary(currency), onTap: () => _showLocationSelector(context)),
                ]),
                _group('Help & about', [
                  _row(ctx, Icons.replay_circle_filled_outlined, 'Replay app tour', onTap: () => _replayTour(context)),
                  _row(ctx, Icons.privacy_tip_outlined, 'Privacy policy', onTap: () => _showPrivacyPolicy(context)),
                  _row(ctx, Icons.gavel_outlined, 'Terms & conditions', onTap: () => _showTerms(context)),
                ]),
                _group('Account', [
                  _row(ctx, Icons.delete_outline_rounded, 'Delete account',
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

  void _showThemeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) {
        final themeService = context.watch<ThemeService>();
        return SafeArea(
          child: Padding(
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
                Text(
                  'Choose Theme',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _themeOption(
                  context,
                  icon: Icons.light_mode_outlined,
                  title: 'Light Mode',
                  isSelected: themeService.themeMode == ThemeMode.light,
                  onTap: () {
                    themeService.setThemeMode(ThemeMode.light);
                    Navigator.pop(context);
                  },
                ),
                _themeOption(
                  context,
                  icon: Icons.dark_mode_outlined,
                  title: 'Dark Mode',
                  isSelected: themeService.themeMode == ThemeMode.dark,
                  onTap: () {
                    themeService.setThemeMode(ThemeMode.dark);
                    Navigator.pop(context);
                  },
                ),
                _themeOption(
                  context,
                  icon: Icons.settings_brightness_outlined,
                  title: 'System Default',
                  isSelected: themeService.themeMode == ThemeMode.system,
                  onTap: () {
                    themeService.setThemeMode(ThemeMode.system);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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



  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.ibmPlexSans(color: AppColors.ink4, fontSize: 13)),
        Text(value, style: GoogleFonts.ibmPlexSans(color: valueColor ?? AppColors.ink, fontWeight: FontWeight.w700, fontSize: 14)),
      ],
    );
  }
}

extension on DateTime {
  String toShortDateString() {
    return '$day/${month.toString().padLeft(2, '0')}/${year.toString().substring(2)}';
  }
}
