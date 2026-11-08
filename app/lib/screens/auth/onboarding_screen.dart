import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/currency.dart';
import '../../core/countries.dart';
import '../../core/theme.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/currency_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/save_portfolio_sheet.dart';
import 'first_trade_flow.dart';

/// Country to pre-select. Many Indian phones run an en_US locale, so the IST
/// offset wins over the locale's country.
String guessCountryCode({Duration? offset, String? localeCountry}) {
  if ((offset ?? DateTime.now().timeZoneOffset) == const Duration(hours: 5, minutes: 30)) return 'IN';
  final c = (localeCountry ?? PlatformDispatcher.instance.locale.countryCode)?.toUpperCase();
  return (c != null && c.length == 2) ? c : 'IN';
}

/// First-run flow, shown once after sign-in (or one-tap guest start) and before
/// the home screen: confirm region and markets, two one-tap questions, then a
/// guided first trade. Onboarding is marked complete only at the very end, so
/// the gate in main.dart keeps this screen up until then.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  @override
  void initState() {
    super.initState();
    ChurnTelemetryService.instance.recordHomeScreen('onboarding_screen');
    _applyCountry(guessCountryCode());
  }

  /// Question steps; the first trade comes after them and has no progress bar.
  static const int _stepCount = 3;
  static const int _tradeStep = 3;

  int _step = 0;
  String? _selectedCountryCode = 'IN';
  TradingLocation? _location = TradingLocation.india;
  Currency? _currency = Currency.inr;
  final Set<String> _markets = {'stock', 'crypto'};
  String? _goal;
  String? _experience;
  bool _saving = false;

  static const _goals = [
    (key: 'learn', title: 'Learn how the market works', subtitle: 'Start from zero, no jargon', icon: Icons.school_outlined),
    (key: 'fno', title: 'Practise F&O before real money', subtitle: 'Options, futures, greeks', icon: Icons.trending_up_rounded),
    (key: 'compete', title: 'Compete and win', subtitle: 'Weekly league and challenges', icon: Icons.emoji_events_outlined),
    (key: 'strategy', title: 'Test a strategy', subtitle: 'Try ideas with real prices', icon: Icons.science_outlined),
  ];

  static const _levels = [
    (key: 'never', title: 'Never', subtitle: 'What’s a call option?', badge: '0'),
    (key: 'little', title: 'A little', subtitle: 'Bought a few stocks, curious about F&O', badge: '1+'),
    (key: 'regular', title: 'Regularly', subtitle: 'I trade with a real broker', badge: '10+'),
  ];

  static const List<({String key, String title, String subtitle, IconData icon})>
      _marketOptions = [
    (
      key: 'stock',
      title: 'Indian Stocks',
      subtitle: 'NSE equities, futures and options',
      icon: Icons.currency_rupee,
    ),
    (
      key: 'us_stock',
      title: 'US Stocks',
      subtitle: 'Apple, Microsoft, Nvidia and more',
      icon: Icons.attach_money,
    ),
    (
      key: 'crypto',
      title: 'Cryptocurrency',
      subtitle: 'Bitcoin, Ethereum and other coins',
      icon: Icons.currency_bitcoin,
    ),
    (
      key: 'pakistan_stock',
      title: 'Pakistan Stocks',
      subtitle: 'PSX equities and market indices',
      icon: Icons.account_balance,
    ),
    (
      key: 'italy_stock',
      title: 'Italy Stocks',
      subtitle: 'Borsa Italiana (Milan) equities',
      icon: Icons.euro,
    ),
  ];

  bool get _canContinue => switch (_step) {
        0 => _selectedCountryCode != null && _markets.isNotEmpty,
        1 => _goal != null,
        _ => _experience != null,
      };

  String _countryFlag(String code) {
    final c = code.trim().toUpperCase();
    if (c.length != 2) return '🌐';
    final first = c.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = c.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  void _selectCountry(String code) => setState(() => _applyCountry(code));

  void _applyCountry(String code) {
    final c = code.trim().toUpperCase();
    {
      _selectedCountryCode = c;
      final loc = c == 'IN' ? TradingLocation.india : TradingLocation.outsideIndia;
      _location = loc;

      if (c == 'IN') {
        _currency = Currency.inr;
        _markets.clear();
        _markets.addAll(['stock', 'crypto']);
      } else if (c == 'PK') {
        _currency = Currency.pkr;
        _markets.clear();
        _markets.addAll(['pakistan_stock', 'crypto']);
      } else if (c == 'IT') {
        _currency = Currency.eur;
        _markets.clear();
        _markets.addAll(['italy_stock', 'crypto']);
      } else if (['FR', 'DE', 'ES', 'NL', 'BE', 'AT', 'PT', 'IE', 'FI', 'GR'].contains(c)) {
        _currency = Currency.eur;
        _markets.clear();
        _markets.addAll(['us_stock', 'crypto']);
      } else {
        _currency = Currency.usd;
        _markets.clear();
        _markets.addAll(['us_stock', 'crypto']);
      }
    }
  }

  Future<void> _next() async {
    if (_step < _stepCount - 1) {
      setState(() => _step++);
      return;
    }
    // Answers are kept locally and in analytics; the server has no column yet.
    unawaited(AnalyticsService.log('onboarding_answers', {
      'country': _selectedCountryCode ?? '',
      'goal': _goal ?? '',
      'experience': _experience ?? '',
    }));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('onboarding_goal', _goal ?? '');
      await prefs.setString('onboarding_experience', _experience ?? '');
    } catch (_) {}
    if (mounted) setState(() => _step = _tradeStep);
  }

  Future<void> _finish({required bool traded}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final isGuest = context.read<AuthService>().isGuest;
    // A guest who just bought something has the most to keep: ask now.
    if (traded && isGuest) await showSavePortfolioSheet(context, trigger: 'onboarding_first_trade');
    // Guests skipped the OS prompt at sign-in; a skipper never saw the alerts card.
    if (!traded) unawaited(NotificationService.instance.setup());
    if (_selectedCountryCode != null) {
      await CurrencyService.instance.setCountryAndState(_selectedCountryCode!);
    }
    await CurrencyService.instance.completeOnboarding(
      currency: _currency ?? Currency.inr,
      markets: _markets.toList(),
      location: _location,
    );
    // The gate in main.dart watches CurrencyService, so completing onboarding
    // swaps this screen for the home shell without an explicit navigation.
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_step == _tradeStep) {
      return Scaffold(
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: _saving,
            child: FirstTradeFlow(markets: _markets.toList(), onFinish: _finish),
          ),
        ),
      );
    }
    final last = _step == _stepCount - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, AppSpacing.md, 20, 0),
            child: Row(children: [
              if (_step > 0) ...[
                AuthIconButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Go back a step',
                    onTap: () {
                      if (!_saving) setState(() => _step--);
                    }),
                const SizedBox(width: AppSpacing.md),
              ] else ...[
                const TitanCrown(size: 26),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text('Quick setup', style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: AppColors.ink)),
              const Spacer(),
              Text('Step ${_step + 1} of $_stepCount', style: AppFonts.mono(size: 12, color: AppColors.ink4)),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Semantics(
              label: 'Setup progress, step ${_step + 1} of $_stepCount',
              child: Row(children: [
                for (var i = 0; i < _stepCount; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 4,
                      margin: EdgeInsets.only(right: i < _stepCount - 1 ? 6 : 0),
                      decoration: BoxDecoration(
                        color: i <= _step ? AppColors.goldMid : AppColors.birch,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          Expanded(
            child: switch (_step) {
              0 => _buildRegionStep(),
              1 => _buildGoalStep(),
              _ => _buildExperienceStep(),
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, AppSpacing.lg),
            child: AuthPrimaryButton(
              label: last ? 'Set up my first trade' : (_step == 0 ? 'Looks right' : 'Continue'),
              busy: _saving,
              onPressed: _canContinue ? _next : null,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _heading(String title, String subtitle) => Padding(
        padding: const EdgeInsets.fromLTRB(20, AppSpacing.xl, 20, AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppFonts.sans(size: 28, weight: FontWeight.w700, color: AppColors.ink, height: 1.15)),
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle, style: AppFonts.sans(size: 15, color: AppColors.ink3, height: 1.45)),
        ]),
      );

  Widget _buildRegionStep() {
    final country = Countries.name(_selectedCountryCode) ?? 'your country';
    return ListView(children: [
      _heading('Looks like you’re in $country',
          'We picked your currency and markets from your phone. You can still trade any market, any time.'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Material(
          color: AppColors.goldPale,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: AppColors.goldMid, width: 1.5)),
          child: InkWell(
            onTap: _showCountryPickerModal,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(children: [
                Text(_countryFlag(_selectedCountryCode ?? 'IN'), style: const TextStyle(fontSize: 30)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(Countries.name(_selectedCountryCode) ?? 'Select country',
                        style: AppFonts.sans(size: 17, weight: FontWeight.w700, color: AppColors.ink)),
                    Text('Prices shown in ${_currency?.symbol ?? ''} ${_currency?.label ?? ''}', style: AppText.bodySmall),
                  ]),
                ),
                Text('Change', style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: AppColors.goldMid)),
              ]),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, AppSpacing.xl, 20, AppSpacing.sm),
        child: Text('YOUR MARKETS · UP TO 3', style: AppText.sectionLabel),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
          for (final m in _marketOptions)
            FilterChip(
              label: Text(m.title),
              selected: _markets.contains(m.key),
              labelStyle: AppFonts.sans(
                  size: 13, weight: FontWeight.w600, color: _markets.contains(m.key) ? AppColors.goldMid : AppColors.ink2),
              side: BorderSide(color: _markets.contains(m.key) ? AppColors.goldMid : AppColors.birch),
              onSelected: (_) => _toggleMarket(m.key),
            ),
        ]),
      ),
    ]);
  }

  void _toggleMarket(String key) => setState(() {
        if (_markets.contains(key)) {
          if (_markets.length > 1) {
            _markets.remove(key);
          } else {
            _snack('Please select at least 1 market.');
          }
        } else if (_markets.length >= 3) {
          _snack('You can select a maximum of 3 markets.');
        } else {
          _markets.add(key);
        }
      });

  void _showCountryPickerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(builder: (modalCtx, setModalState) {
          final q = filter.trim().toLowerCase();
          final matches = q.isEmpty
              ? Countries.sortedByName
              : Countries.sortedByName
                  .where((e) => e.value.toLowerCase().contains(q) || e.key.toLowerCase().contains(q))
                  .toList();
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, AppSpacing.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Select country', style: AppFonts.sans(size: 18, weight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                        hintText: 'Search countries', prefixIcon: Icon(Icons.search_rounded, color: AppColors.ink4)),
                    onChanged: (val) => setModalState(() => filter = val),
                  ),
                ]),
              ),
              Divider(color: AppColors.birch),
              Expanded(
                child: ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (c, i) {
                    final code = matches[i].key;
                    final selected = _selectedCountryCode == code;
                    return ListTile(
                      leading: Text(_countryFlag(code), style: const TextStyle(fontSize: 22)),
                      title: Text(matches[i].value,
                          style: AppFonts.sans(
                              size: 14,
                              weight: selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? AppColors.goldMid : AppColors.ink)),
                      trailing: selected
                          ? Icon(Icons.check_rounded, color: AppColors.goldMid, size: 20)
                          : Text(code, style: AppFonts.mono(size: 12, color: AppColors.ink5)),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _selectCountry(code);
                      },
                    );
                  },
                ),
              ),
            ]),
          );
        });
      },
    );
  }

  Widget _buildGoalStep() => ListView(children: [
        _heading('What brings you here?', 'We’ll set up your first trade around it.'),
        for (final g in _goals)
          _option(
            selected: _goal == g.key,
            title: g.title,
            subtitle: g.subtitle,
            leading: Icon(g.icon, size: 22, color: _goal == g.key ? AppColors.goldMid : AppColors.ink4),
            onTap: () => setState(() => _goal = g.key),
          ),
      ]);

  Widget _buildExperienceStep() => ListView(children: [
        _heading('How much have you traded?', 'So we explain just enough — not too much, not too little.'),
        for (final l in _levels)
          _option(
            selected: _experience == l.key,
            title: l.title,
            subtitle: l.subtitle,
            leading: Text(l.badge,
                style: AppFonts.mono(size: 14, weight: FontWeight.w600, color: _experience == l.key ? AppColors.goldMid : AppColors.ink4)),
            onTap: () => setState(() => _experience = l.key),
          ),
      ]);

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));

  /// One selectable row: accent fill and border when selected, a square check
  /// for multi-select (markets) or a round mark for single-select (currency).
  Widget _option({
    required bool selected,
    required String title,
    required String subtitle,
    required Widget leading,
    required VoidCallback onTap,
    bool isCheckbox = false,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, AppSpacing.sm),
        child: Semantics(
          inMutuallyExclusiveGroup: !isCheckbox,
          checked: selected,
          label: '$title. $subtitle',
          child: Material(
            color: selected ? AppColors.goldPale : AppColors.pureWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: selected ? AppColors.goldMid : AppColors.birch, width: selected ? 1.5 : 1),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
                child: Row(children: [
                  SizedBox(width: 28, child: Center(child: leading)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: AppFonts.sans(size: 15, weight: FontWeight.w600, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: AppText.bodySmall),
                    ]),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.imperialGold : Colors.transparent,
                      shape: isCheckbox ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: isCheckbox ? BorderRadius.circular(6) : null,
                      border: Border.all(color: selected ? AppColors.imperialGold : AppColors.ink5, width: 2),
                    ),
                    child: selected ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
