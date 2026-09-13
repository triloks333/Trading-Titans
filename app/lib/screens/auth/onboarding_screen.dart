import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/currency.dart';
import '../../core/theme.dart';
import '../../services/currency_service.dart';
import '../../widgets/crown_logo.dart';

/// First-run questions, shown once after sign-in and before the home screen.
///
/// Two answers: the currency everything is displayed in, and which markets the
/// user cares about. Both are changeable later from Profile, so nothing here is
/// a one-way door — which is why there is no "are you sure?" step.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _stepCount = 3;

  int _step = 0;
  TradingLocation? _location;
  Currency? _currency;
  final Set<String> _markets = {};
  bool _saving = false;

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
  ];

  bool get _canContinue => switch (_step) {
        0 => _location != null,
        1 => _currency != null,
        _ => _markets.isNotEmpty,
      };

  /// Applies the location's suggestions without overwriting a choice the user
  /// has already made by going back and forth.
  void _selectLocation(TradingLocation location) {
    setState(() {
      _location = location;
      _currency ??= location.suggestedCurrency;
      if (_markets.isEmpty) _markets.addAll(location.suggestedMarkets);
    });
  }

  Future<void> _next() async {
    if (_step < _stepCount - 1) {
      setState(() => _step++);
      return;
    }
    setState(() => _saving = true);
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
    return Scaffold(
      backgroundColor: AppColors.parchment,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  const CrownLogo(size: 28),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Trading Titans',
                    style: GoogleFonts.inter(
                        fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink),
                  ),
                  const Spacer(),
                  if (_step > 0)
                    Semantics(
                      button: true,
                      label: 'Go back a step',
                      child: GestureDetector(
                        onTap: _saving ? null : () => setState(() => _step--),
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.md),
                          child: Text('Back',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.imperialGold)),
                        ),
                      ),
                    ),
                  Text(
                    'Step ${_step + 1} of $_stepCount',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: LinearProgressIndicator(
                  value: (_step + 1) / _stepCount,
                  minHeight: 5,
                  backgroundColor: AppColors.cream,
                  valueColor: const AlwaysStoppedAnimation(AppColors.imperialGold),
                  semanticsLabel: 'Setup progress',
                ),
              ),
            ),
            Expanded(
              child: switch (_step) {
                0 => _buildLocationStep(),
                1 => _buildCurrencyStep(),
                _ => _buildMarketsStep(),
              },
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (!_canContinue || _saving) ? null : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    foregroundColor: AppColors.pureWhite,
                    disabledBackgroundColor: AppColors.birch,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          _step < _stepCount - 1 ? 'Continue' : 'Start trading',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeading(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(
            left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.xl, bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.inter(
                    fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(subtitle,
                style: GoogleFonts.inter(
                    fontSize: 14, color: AppColors.ink4, height: 1.4)),
          ],
        ),
      );

  Widget _buildLocationStep() {
    return ListView(
      children: [
        _buildHeading(
          'Where are you trading from?',
          'This sets up sensible defaults for you. You can change everything '
              'afterwards, and you can trade any market either way.',
        ),
        for (final l in TradingLocation.values)
          _buildOptionCard(
            selected: _location == l,
            title: l.label,
            subtitle: l.subtitle,
            leading: Icon(
              l == TradingLocation.india ? Icons.home_outlined : Icons.public,
              size: 22,
              color: _location == l ? AppColors.imperialGold : AppColors.ink4,
            ),
            onTap: () => _selectLocation(l),
          ),
      ],
    );
  }

  Widget _buildCurrencyStep() {
    return ListView(
      children: [
        _buildHeading(
          'Which currency should we use?',
          'Every price, balance and profit figure in the app will be shown in '
              'this currency. You can change it any time from your profile.',
        ),
        for (final c in Currency.values)
          _buildOptionCard(
            selected: _currency == c,
            title: c.label,
            subtitle: c.subtitle,
            leading: Text(
              c.symbol,
              style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _currency == c ? AppColors.imperialGold : AppColors.ink4),
            ),
            onTap: () => setState(() => _currency = c),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'Your wallet is held in rupees. Choosing dollars converts what you '
            'see at the live exchange rate; it does not change what you own.',
            style: GoogleFonts.inter(
                fontSize: 11, color: AppColors.ink5, fontStyle: FontStyle.italic, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildMarketsStep() {
    return ListView(
      children: [
        _buildHeading(
          'What do you want to trade?',
          'Pick everything that interests you. We will open your favourite '
              'market first. You can still trade anything, any time.',
        ),
        for (final m in _marketOptions)
          _buildOptionCard(
            selected: _markets.contains(m.key),
            title: m.title,
            subtitle: m.subtitle,
            leading: Icon(m.icon,
                size: 22,
                color: _markets.contains(m.key)
                    ? AppColors.imperialGold
                    : AppColors.ink4),
            isCheckbox: true,
            onTap: () => setState(() {
              if (!_markets.remove(m.key)) _markets.add(m.key);
            }),
          ),
        if (_markets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              'Choose at least one to continue.',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4),
            ),
          ),
      ],
    );
  }

  Widget _buildOptionCard({
    required bool selected,
    required String title,
    required String subtitle,
    required Widget leading,
    required VoidCallback onTap,
    bool isCheckbox = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Semantics(
        // Announces as a radio for the currency step and a checkbox for markets,
        // which is what each control actually is.
        inMutuallyExclusiveGroup: !isCheckbox,
        checked: selected,
        label: '$title. $subtitle',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.pureWhite,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected ? AppColors.imperialGold : AppColors.birch,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected ? AppShadows.sm : null,
            ),
            child: Row(
              children: [
                SizedBox(width: 28, child: Center(child: leading)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.ink4, height: 1.3)),
                    ],
                  ),
                ),
                Icon(
                  isCheckbox
                      ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                      : (selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                  size: 22,
                  color: selected ? AppColors.imperialGold : AppColors.ink5,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
