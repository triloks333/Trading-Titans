import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/currency.dart';
import '../../core/countries.dart';
import '../../core/theme.dart';
import '../../services/currency_service.dart';
import '../../widgets/crown_logo.dart';

/// First-run questions, shown once after sign-in and before the home screen.
///
/// Three answers: country/residency, display currency, and preferred markets.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _stepCount = 3;

  int _step = 0;
  String? _selectedCountryCode = 'IN';
  TradingLocation? _location = TradingLocation.india;
  Currency? _currency = Currency.inr;
  final Set<String> _markets = {'stock', 'crypto'};
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
        0 => _selectedCountryCode != null,
        1 => _currency != null,
        _ => _markets.isNotEmpty,
      };

  String _countryFlag(String code) {
    final c = code.trim().toUpperCase();
    if (c.length != 2) return '🌐';
    final first = c.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = c.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  void _selectCountry(String code) {
    final c = code.trim().toUpperCase();
    setState(() {
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
    });
  }

  Future<void> _next() async {
    if (_step < _stepCount - 1) {
      setState(() => _step++);
      return;
    }
    setState(() => _saving = true);
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
    final countryName = Countries.name(_selectedCountryCode) ?? 'Select Country';
    final flag = _countryFlag(_selectedCountryCode ?? 'IN');

    const popularCodes = ['IN', 'PK', 'IT', 'US', 'GB', 'AE'];

    return ListView(
      children: [
        _buildHeading(
          'Where are you trading from?',
          'Select your country to set up your preferred market and currency automatically. You can always change it later.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: GestureDetector(
            onTap: _showCountryPickerModal,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.pureWhite,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.imperialGold, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.imperialGold.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Text(flag, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          countryName,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap to choose from 250+ countries',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_circle_outlined, color: AppColors.imperialGold, size: 24),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
          child: Text(
            'QUICK SELECT',
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.ink4, letterSpacing: 0.5),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: popularCodes.map((code) {
              final isSelected = _selectedCountryCode == code;
              final name = Countries.name(code) ?? code;
              return ChoiceChip(
                label: Text('${_countryFlag(code)} $name'),
                selected: isSelected,
                selectedColor: AppColors.imperialGold,
                backgroundColor: AppColors.pureWhite,
                labelStyle: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.ink,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? AppColors.imperialGold : AppColors.birch,
                  ),
                ),
                onSelected: (_) => _selectCountry(code),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.ink4, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Pre-selected currency: ${_currency?.symbol ?? ''} ${_currency?.label ?? ''}',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showCountryPickerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final all = Countries.sortedByName;
            final matches = filter.trim().isEmpty
                ? all
                : all.where((e) {
                    final q = filter.trim().toLowerCase();
                    return e.value.toLowerCase().contains(q) || e.key.toLowerCase().contains(q);
                  }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: AppColors.pureWhite,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.birch,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          'Select Country',
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 4),
                    child: TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search countries...',
                        prefixIcon: Icon(Icons.search, size: 20, color: AppColors.ink4),
                        filled: true,
                        fillColor: AppColors.parchment,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) => setModalState(() => filter = val),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (c, idx) {
                        final item = matches[idx];
                        final code = item.key;
                        final name = item.value;
                        final isSelected = _selectedCountryCode == code;
                        return ListTile(
                          leading: Text(_countryFlag(code), style: const TextStyle(fontSize: 24)),
                          title: Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppColors.imperialGold : AppColors.ink,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: AppColors.imperialGold, size: 20)
                              : Text(code, style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink5)),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _selectCountry(code);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
            'Your virtual wallet balance is dynamically converted to your chosen currency at the live rate. You can switch currencies at any time.',
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
          'Pick up to 3 markets that interest you. You can change your choice anytime from the Trade screen.',
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
              if (_markets.contains(m.key)) {
                if (_markets.length > 1) {
                  _markets.remove(m.key);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select at least 1 market.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } else {
                if (_markets.length >= 3) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('You can select a maximum of 3 markets.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                _markets.add(m.key);
              }
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
