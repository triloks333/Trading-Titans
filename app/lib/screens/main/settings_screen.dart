import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/countries.dart';
import '../../core/currency.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/app_flags_service.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/currency_service.dart';
import '../../services/plan_service.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../services/tour_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/legal_sheet.dart';
import 'chat_screen.dart';
import 'convert_account_screen.dart';
import 'glossary_screen.dart';
import 'notifications_screen.dart';
import 'subscribe_screen.dart';
import 'watchlist_screen.dart';

/// Market keys for preferences, in display order.
const List<(String, String)> kPreferenceMarkets = [
  ('stock', 'Indian stocks'),
  ('us_stock', 'US stocks'),
  ('crypto', 'Crypto'),
  ('italy_stock', 'Italy stocks'),
  ('pakistan_stock', 'Pakistan stocks'),
];

/// "Maharashtra, India" from the most specific answer on file; the coarse
/// india/outside_india label for accounts that answered before the country question.
String locationSummary(CurrencyService c) {
  final country = Countries.name(c.countryCode);
  if (country == null) return c.location?.label ?? 'Not set';
  return c.state == null ? country : '${c.state}, $country';
}

// ── Shared pieces ─────────────────────────────────────────────────────────────

Widget _header(BuildContext context, String title, {bool theme = true}) => Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
      child: Row(children: [
        AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink))),
        if (theme)
          ListenableBuilder(
            listenable: ThemeService(),
            builder: (_, _) => AuthIconButton(
              icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              label: 'Toggle light or dark theme',
onTap: () {
                ChurnTelemetryService.instance.recordButtonTap('global_theme_dark_light_toggle');
                ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark);
              },
            ),
          ),
      ]),
    );

Widget _caption(String text) =>
    Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 22, AppSpacing.lg, 8), child: Text(text.toUpperCase(), style: AppText.sectionLabel));

Widget _group(List<Widget> rows) => Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[if (i > 0) Divider(color: AppColors.birch), rows[i]],
      ]),
    );

Widget _item(IconData icon, String label,
        {String? sub, Widget? subWidget, String? value, bool mono = false, Widget? trailing, Color? color, bool chevron = true, VoidCallback? onTap}) =>
    InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            Icon(icon, size: 20, color: color ?? AppColors.ink3),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: AppFonts.sans(size: 14, weight: FontWeight.w500, color: color ?? AppColors.ink)),
                if (sub != null) Text(sub, style: AppFonts.sans(size: 12, color: AppColors.ink4)),
                ?subWidget,
              ]),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Text(value, style: (mono ? AppFonts.mono : AppFonts.sans)(size: 12, color: AppColors.ink4)),
            ],
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
            if (chevron && onTap != null) ...[const SizedBox(width: 4), Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.ink4)],
          ]),
        ),
      ),
    );

Widget _pill(String text) => Container(
      margin: const EdgeInsets.only(right: 4, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppColors.goldPale, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: AppFonts.sans(size: 12, weight: FontWeight.w500, color: AppColors.goldMid)),
    );

/// System / Light / Dark, one tap.
Widget themeSegments({bool icons = false}) => ListenableBuilder(
      listenable: ThemeService(),
      builder: (_, _) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(children: [
          for (final (i, (mode, label, icon)) in const [
            (ThemeMode.system, 'System', Icons.desktop_windows_outlined),
            (ThemeMode.light, 'Light', Icons.light_mode_outlined),
            (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                button: true,
                selected: ThemeService().themeMode == mode,
                label: '$label theme',
                excludeSemantics: true,
                child: GestureDetector(
onTap: () {
                    ChurnTelemetryService.instance.recordButtonTap('global_theme_dark_light_toggle');
                    ThemeService().setThemeMode(mode);
                  },
                  child: Container(
                    height: icons ? 40 : 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ThemeService().themeMode == mode ? AppColors.pureWhite : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icons) ...[Icon(icon, size: 16, color: ThemeService().themeMode == mode ? AppColors.ink : AppColors.ink3), const SizedBox(width: 6)],
                      Text(label,
                          style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: ThemeService().themeMode == mode ? AppColors.ink : AppColors.ink3)),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    );

// ── Settings ──────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  int? _watchlists;
  bool? _chatMuted;
  Map<String, bool>? _prefs;

  /// The four push switches: key, label, description, icon.
  static const _switches = [
    ('price', 'Price alerts', 'When a stock crosses your target', Icons.show_chart_rounded),
    ('orders', 'Order updates', 'Fills, rejections and cancellations', Icons.check_rounded),
    ('league', 'League & rewards', 'Rank changes and challenge payouts', Icons.emoji_events_outlined),
    ('news', 'News', 'Daily market headlines', Icons.article_outlined),
  ];

  /// Optimistic: flips at once, reverts with a message if the save fails.
  Future<void> _setPref(String key, bool on) async {
    final before = _prefs?[key];
    setState(() => _prefs = {...?_prefs, key: on});
    try {
      await SupabaseService().setNotificationPref(key, on);
    } catch (_) {
      if (!mounted) return;
      setState(() => _prefs = {...?_prefs, key: before ?? true});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save that. Check your connection.")));
    }
  }

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    }).catchError((_) {});
    SupabaseService().getWatchlists().then((l) {
      if (mounted) setState(() => _watchlists = l.length);
    }).catchError((_) {});
    SupabaseService().getNotificationPrefs().then((p) {
      if (mounted) setState(() => _prefs = p);
    }).catchError((_) {
      if (mounted) setState(() => _prefs = const {'price': true, 'orders': true, 'league': true, 'news': true});
    });
    ChatService.isChatMuted().then((m) {
      if (mounted) setState(() => _chatMuted = m);
    }).catchError((_) {});
  }

  Future<void> _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _replayTour() async {
    final messenger = ScaffoldMessenger.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pending_tour_replay', true);
    TourService.requestReplay();
    messenger.showSnackBar(const SnackBar(content: Text('Starting the app tour…')));
  }

  Future<void> _rate() async {
    final market = Uri.parse('market://details?id=com.kwm.tradingtitans');
    if (await launchUrl(market, mode: LaunchMode.externalApplication).catchError((_) => false)) return;
    await launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=com.kwm.tradingtitans'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final currency = context.watch<CurrencyService>();
    final plan = context.watch<PlanService>();
    final monetized = context.watch<AppFlagsService>().monetizationEnabled;
    final email = auth.user?.email ?? '';
    final provider = SupabaseService().currentUser?.appMetadata['provider'] as String?;
    final markets = [for (final (k, l) in kPreferenceMarkets) if (currency.preferredMarkets.contains(k)) l];

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _header(context, 'Settings', theme: false),
          Expanded(
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              _caption('Appearance'),
              _group([
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('App theme', style: AppFonts.sans(size: 14, weight: FontWeight.w500, color: AppColors.ink)),
                    const SizedBox(height: 10),
                    themeSegments(),
                  ]),
                ),
                _item(Icons.currency_exchange_rounded, 'Display currency',
                    sub: 'Changes every price and balance shown',
                    value: '${currency.displayCurrency.code} ${currency.displayCurrency.symbol.trim()}',
                    onTap: () => _push(const PreferencesScreen())),
              ]),
              _caption('Trading'),
              _group([
                _item(Icons.tune_rounded, 'Preferred markets',
                    subWidget: Wrap(children: [for (final m in markets) _pill(m)]),
                    value: '${markets.length}/3',
                    mono: true,
                    onTap: () => _push(const PreferencesScreen())),
                _item(Icons.place_outlined, 'Trading from',
                    sub: 'Sets billing currency only', value: locationSummary(currency), onTap: () => _push(const PreferencesScreen())),
                _item(Icons.star_outline_rounded, 'Manage watchlists',
                    value: _watchlists == null ? null : '$_watchlists ${_watchlists == 1 ? 'list' : 'lists'}',
                    mono: true,
                    onTap: () => _push(const WatchlistScreen())),
              ]),
              _caption('Notifications'),
              _group([
                for (final (key, label, desc, icon) in _switches)
                  MergeSemantics(
                    child: _item(icon, label,
                        sub: desc,
                        chevron: false,
                        onTap: _prefs == null ? null : () => _setPref(key, !(_prefs![key] ?? true)),
                        trailing: Switch(
                          value: _prefs?[key] ?? true,
                          onChanged: _prefs == null ? null : (v) => _setPref(key, v),
                        )),
                  ),
                _item(Icons.notifications_none_rounded, 'Notification inbox',
                    sub: 'Switched-off types still land here', onTap: () => _push(const NotificationsScreen())),
                _item(Icons.chat_bubble_outline_rounded, 'Titans Room chat',
                    sub: '@everyone and @mentions always notify',
                    value: _chatMuted == null ? null : (_chatMuted! ? 'Muted' : 'Active'),
                    onTap: () => _push(const ChatScreen())),
              ]),
              _caption('Account'),
              _group([
                _item(Icons.mail_outline_rounded, 'Email',
                    sub: auth.isGuest ? 'Guest account' : email,
                    chevron: false,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: AppCard.badge(AppColors.cream),
                      child: Text(auth.isGuest ? 'GUEST' : (provider ?? 'email').toUpperCase(), style: AppText.badge.copyWith(color: AppColors.ink3)),
                    )),
                if (auth.isGuest)
                  _item(Icons.lock_open_rounded, 'Make account permanent',
                      sub: 'Get ${Money.wallet(1100, decimals: 0)} and keep your progress',
                      color: AppColors.titanGold,
                      onTap: () => _push(const ConvertAccountScreen())),
                if (monetized)
                  _item(Icons.workspace_premium_outlined, 'Subscription',
                      value: plan.isPaid ? '${plan.tier[0].toUpperCase()}${plan.tier.substring(1)}' : 'Free plan',
                      onTap: () => _push(const SubscribeScreen())),
                _item(Icons.logout_rounded, 'Sign out', chevron: false, onTap: () async {
                  ChurnTelemetryService.instance.recordButtonTap('settings_sign_out_btn');
                  final nav = Navigator.of(context);
                  await auth.logout();
                  nav.popUntil((r) => r.isFirst);
                }),
                _item(Icons.delete_outline_rounded, 'Delete account',
                    sub: 'Permanently removes all data', color: AppColors.bear, chevron: false, onTap: () {
                      ChurnTelemetryService.instance.recordButtonTap('settings_delete_account_danger_btn');
                      showDeleteAccountDialog(context);
                    }),
              ]),
              _caption('Help & about'),
              _group([
                _item(Icons.play_circle_outline_rounded, 'Replay app tour', chevron: false, onTap: () {
                  ChurnTelemetryService.instance.recordButtonTap('profile_replay_showcase_tour_btn');
                  _replayTour();
                }),
                _item(Icons.school_outlined, 'Trading glossary', onTap: () => _push(const GlossaryScreen())),
                _item(Icons.star_rate_outlined, 'Rate Trading Titans', sub: 'On Google Play', chevron: false, onTap: _rate),
                _item(Icons.gavel_outlined, 'Terms & conditions', onTap: () => _push(const LegalScreen())),
                _item(Icons.privacy_tip_outlined, 'Privacy policy', onTap: () => _push(const LegalScreen(privacy: true))),
              ]),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(children: [
                  GestureDetector(
                    onTap: () {
                      ChurnTelemetryService.instance.recordButtonTap('profile_open_support_tickets_row_btn');
                      _push(const ChatScreen(initialTab: 1));
                    },
                    child: Text.rich(
                      TextSpan(style: AppFonts.sans(size: 11, color: AppColors.ink4), children: [
                        const TextSpan(text: 'Need help? Use Tickets in '),
                        TextSpan(text: 'Titans Room', style: TextStyle(color: AppColors.goldMid)),
                        const TextSpan(text: '.'),
                      ]),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Text('Trading Titans${_version.isEmpty ? '' : ' v$_version'} · Kashivwealth Management LLP',
                      textAlign: TextAlign.center, style: AppFonts.sans(size: 11, color: AppColors.ink4)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Preferences ───────────────────────────────────────────────────────────────

/// Theme, display currency, preferred markets and trading-from, saved together.
/// The theme applies at once; the rest apply on Save.
class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  final _service = CurrencyService.instance;
  late Currency _currency = _service.displayCurrency;
  late final Set<String> _markets = _service.preferredMarkets.toSet();
  late String? _country = _service.countryCode;
  late String? _state = _service.state;
  bool _maxHit = false;
  bool _saving = false;

  void _toggle(String key) => setState(() {
        if (_markets.contains(key)) {
          // Never empty: the nav bar and default tab need at least one market.
          if (_markets.length > 1) _markets.remove(key);
          _maxHit = false;
        } else if (_markets.length >= 3) {
          _maxHit = true;
        } else {
          _markets.add(key);
          _maxHit = false;
        }
      });

  Future<void> _pickCountry() async {
    final code = await pickFromList(context,
        title: 'Country',
        subtitle: 'Sets the currency you are billed in. It does not restrict any market.',
        options: Countries.sortedByName,
        selected: _country);
    if (code == null) return;
    setState(() {
      // A state belongs to its country; a new country starts without one.
      if (code != _country) _state = null;
      _country = code;
    });
  }

  Future<void> _pickState() async {
    final states = Countries.subdivisionsOf(_country);
    if (states.isEmpty) return;
    final s = await pickFromList(context,
        title: 'State', subtitle: 'Optional.', options: [for (final s in states) MapEntry(s, s)], selected: _state);
    if (s != null) setState(() => _state = s);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    if (_currency != _service.displayCurrency) await _service.setDisplayCurrency(_currency);
    if (!_setEquals(_markets, _service.preferredMarkets.toSet())) await _service.setPreferredMarkets(_markets.toList());
    if (_country != null && (_country != _service.countryCode || _state != _service.state)) {
      await _service.setCountryAndState(_country!, state: _state ?? '');
    }
    if (mounted) nav.maybePop();
  }

  static bool _setEquals(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  Widget _option({required Widget leading, required String label, required bool on, required VoidCallback onTap, Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: on ? AppColors.goldPale : AppColors.pureWhite,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: on ? AppColors.goldMid : AppColors.birch)),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                leading,
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: AppFonts.sans(size: 14, weight: FontWeight.w500, color: AppColors.ink))),
                ?trailing,
              ]),
            ),
          ),
        ),
      );

  Widget _section(String title, String? help, List<Widget> children, {Widget? side}) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 22, AppSpacing.lg, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: Text(title.toUpperCase(), style: AppText.sectionLabel)), ?side]),
          if (help != null) Padding(padding: const EdgeInsets.only(top: 6, bottom: 10), child: Text(help, style: AppFonts.sans(size: 12, color: AppColors.ink4)))
          else const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _select(String label, String value, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppFonts.sans(size: 12, color: AppColors.ink3)),
          const SizedBox(height: 4),
          Material(
            color: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: onTap,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Expanded(child: Text(value, style: AppFonts.sans(size: 14, weight: FontWeight.w500, color: onTap == null ? AppColors.ink4 : AppColors.ink))),
                  Icon(Icons.expand_more_rounded, color: AppColors.ink4),
                ]),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final hasStates = Countries.subdivisionsOf(_country).isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _header(context, 'Preferences', theme: false),
          Expanded(
            child: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
              _section('App theme', null, [themeSegments(icons: true)]),
              _section('Display currency', 'Changes every price, balance and profit figure in the app. Your wallet is still held in rupees.', [
                for (final c in Currency.values)
                  _option(
                    leading: SizedBox(width: 28, child: Text(c.symbol.trim(), style: AppFonts.mono(size: 14, weight: FontWeight.w600, color: AppColors.goldMid))),
                    label: '${c.label} · ${c.code}',
                    on: _currency == c,
                    onTap: () => setState(() => _currency = c),
                    trailing: _currency == c ? Text('✓', style: AppFonts.mono(size: 14, color: AppColors.goldMid)) : null,
                  ),
              ]),
              _section(
                'Preferred markets',
                'We open your favourite market first. You can still trade anything, any time.',
                side: Text('${_markets.length}/3', style: AppFonts.mono(size: 12, color: AppColors.ink4)),
                [
                  for (final (k, l) in kPreferenceMarkets)
                    _option(
                      leading: const SizedBox.shrink(),
                      label: l,
                      on: _markets.contains(k),
                      onTap: () => _toggle(k),
                      trailing: Semantics(
                        checked: _markets.contains(k),
                        child: Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _markets.contains(k) ? AppColors.imperialGold : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: _markets.contains(k) ? null : Border.all(color: AppColors.birch, width: 2),
                          ),
                          child: _markets.contains(k) ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                        ),
                      ),
                    ),
                  if (_maxHit)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Text('You can select a maximum of 3 markets at a time.', style: AppFonts.sans(size: 12, color: AppColors.titanGold)),
                    ),
                ],
              ),
              _section('Trading from', 'Sets the currency you are billed in: India is billed in rupees, everywhere else in dollars. It does not restrict any market.', [
                _select('Country', Countries.name(_country) ?? 'Not set', _pickCountry),
                _select('State (optional)', _state ?? 'Not set', hasStates ? _pickState : null),
              ]),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.lg, 16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.birch))),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A searchable single-select sheet returning the chosen key, or null if
/// dismissed. The search matters at 249 countries: the wrong country is the
/// wrong billing currency.
Future<String?> pickFromList(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<MapEntry<String, String>> options,
  String? selected,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) {
        var query = '';
        final media = MediaQuery.of(sheet);
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SizedBox(
            // Fixed height so the list builds lazily rather than all 249 rows per keystroke.
            height: media.size.height * 0.75,
            child: StatefulBuilder(builder: (context, setSheet) {
              final needle = query.trim().toLowerCase();
              final shown = needle.isEmpty ? options : options.where((e) => e.value.toLowerCase().contains(needle)).toList();
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: AppFonts.sans(size: 18, weight: FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: AppFonts.sans(size: 12, color: AppColors.ink4)),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      onChanged: (v) => setSheet(() => query = v),
                      decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search, size: 20)),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: shown.isEmpty
                          ? Center(child: Text('No matches', style: AppText.body))
                          : ListView.builder(
                              itemCount: shown.length,
                              itemBuilder: (_, i) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(shown[i].value,
                                    style: AppFonts.sans(size: 15, weight: shown[i].key == selected ? FontWeight.w700 : FontWeight.w500, color: AppColors.ink)),
                                trailing: shown[i].key == selected ? Icon(Icons.check, size: 18, color: AppColors.goldMid) : null,
                                onTap: () => Navigator.pop(context, shown[i].key),
                              ),
                            ),
                    ),
                  ]),
                ),
              );
            }),
          ),
        );
      },
    );

// ── Delete account ────────────────────────────────────────────────────────────

/// "Delete account?" with what goes, gated on typing DELETE.
Future<void> showDeleteAccountDialog(BuildContext context) => showDialog(
      context: context,
      barrierColor: const Color(0x9E03060A),
      builder: (_) => const DeleteAccountDialog(),
    );

class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _typed = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _ok => _typed.text.trim().toUpperCase() == 'DELETE';

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final auth = context.read<AuthService>();
    final nav = Navigator.of(context, rootNavigator: true);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.deleteAccount();
      nav.popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst(RegExp(r'^(Exception|_Exception):\s*'), '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<AuthService>().user?.walletBalance ?? 0;
    Widget line(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Text('✕', style: AppFonts.sans(size: 13, color: AppColors.bear)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppFonts.sans(size: 13, color: AppColors.ink3))),
          ]),
        );
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: AppColors.bearLight, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.delete_outline_rounded, size: 26, color: AppColors.bear),
            ),
          ),
          const SizedBox(height: 14),
          Text('Delete account?', style: AppFonts.sans(size: 22, weight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          Text.rich(TextSpan(style: AppFonts.sans(size: 14, color: AppColors.ink3), children: [
            const TextSpan(text: 'This will immediately remove everything below. '),
            TextSpan(text: 'This action is irreversible.', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.bear)),
          ])),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Column(children: [
              line('Profile and Titans Room messages'),
              line('Trade history & holdings'),
              line('Demo cash ${Money.wallet(wallet, decimals: 2)}'),
              line('League rankings & Titan level'),
            ]),
          ),
          const SizedBox(height: 14),
          Text.rich(TextSpan(style: AppFonts.sans(size: 12, color: AppColors.ink3), children: [
            const TextSpan(text: 'Type '),
            TextSpan(text: 'DELETE', style: AppFonts.mono(size: 12, weight: FontWeight.w700, color: AppColors.ink)),
            const TextSpan(text: ' to confirm'),
          ])),
          const SizedBox(height: 6),
          TextField(
            controller: _typed,
            autocorrect: false,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            style: AppFonts.mono(size: 15, weight: FontWeight.w500, color: AppColors.ink),
            onChanged: (_) => setState(() {}),
          ),
          if (_busy) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Deleting account…', textAlign: TextAlign.center, style: AppText.body)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: AppFonts.sans(size: 12, color: AppColors.bear))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(backgroundColor: AppColors.cream),
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.bear),
                onPressed: _ok && !_busy ? _delete : null,
                child: const Text('Delete permanently'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
