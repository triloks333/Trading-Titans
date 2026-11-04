import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/countries.dart';
import '../core/currency.dart';
import '../core/theme.dart';
import '../services/currency_service.dart';

/// Modal dialog presented to existing users upon update rollout, ensuring every
/// user sets their specific country and chooses their preferred display currency.
class CountryCurrencyUpdateDialog extends StatefulWidget {
  const CountryCurrencyUpdateDialog({super.key});

  /// Checks if the update dialog should be shown and shows it if needed.
  static Future<void> checkAndShow(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final confirmed = prefs.getBool('v2_country_currency_confirmed') ?? false;
      final currentCountry = CurrencyService.instance.countryCode;

      // Show if user hasn't explicitly confirmed their country & currency in this update,
      // or if they only had the old coarse inside_india/outside_india flag without a country code.
      if (!confirmed || currentCountry == null) {
        if (!context.mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const CountryCurrencyUpdateDialog(),
        );
      }
    } catch (e) {
      debugPrint('CountryCurrencyUpdateDialog.checkAndShow failed: $e');
    }
  }

  @override
  State<CountryCurrencyUpdateDialog> createState() =>
      _CountryCurrencyUpdateDialogState();
}

class _CountryCurrencyUpdateDialogState
    extends State<CountryCurrencyUpdateDialog> {
  late String _selectedCountry;
  late Currency _selectedCurrency;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final service = CurrencyService.instance;
    _selectedCountry = service.countryCode ?? 'IN';
    _selectedCurrency = service.displayCurrency;
  }

  String _countryFlag(String code) {
    final c = code.trim().toUpperCase();
    if (c.length != 2) return '🌐';
    final first = c.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = c.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  void _onCountrySelected(String code) {
    final c = code.trim().toUpperCase();
    setState(() {
      _selectedCountry = c;
      if (c == 'IN') {
        _selectedCurrency = Currency.inr;
      } else if (c == 'PK') {
        _selectedCurrency = Currency.pkr;
      } else if (c == 'IT' ||
          ['FR', 'DE', 'ES', 'NL', 'BE', 'AT', 'PT', 'IE', 'FI', 'GR']
              .contains(c)) {
        _selectedCurrency = Currency.eur;
      } else {
        _selectedCurrency = Currency.usd;
      }
    });
  }

  void _showCountryPicker() {
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
                    return e.value.toLowerCase().contains(q) ||
                        e.key.toLowerCase().contains(q);
                  }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: AppColors.pureWhite,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          'Select Your Country',
                          style: GoogleFonts.ibmPlexSans(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.ink),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close, color: AppColors.ink),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: 4),
                    child: TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search 250+ countries...',
                        hintStyle: GoogleFonts.ibmPlexSans(color: AppColors.ink5),
                        prefixIcon: Icon(Icons.search,
                            size: 20, color: AppColors.ink4),
                        filled: true,
                        fillColor: AppColors.cream,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) => setModalState(() => filter = val),
                    ),
                  ),
                  Divider(height: 1, color: AppColors.birch),
                  Expanded(
                    child: ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (c, idx) {
                        final item = matches[idx];
                        final code = item.key;
                        final name = item.value;
                        final isSelected = _selectedCountry == code;
                        return ListTile(
                          leading: Text(_countryFlag(code),
                              style: const TextStyle(fontSize: 24)),
                          title: Text(
                            name,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? AppColors.imperialGold
                                  : AppColors.ink,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(Icons.check_circle,
                                  color: AppColors.imperialGold, size: 20)
                              : Text(code,
                                  style: GoogleFonts.ibmPlexSans(
                                      fontSize: 12, color: AppColors.ink5)),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _onCountrySelected(code);
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await CurrencyService.instance.setCountryAndState(_selectedCountry);
      await CurrencyService.instance.setDisplayCurrency(_selectedCurrency);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('v2_country_currency_confirmed', true);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Error saving region/currency preferences: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const popularCodes = ['IN', 'PK', 'IT', 'US', 'GB', 'AE'];
    final countryName = Countries.name(_selectedCountry) ?? _selectedCountry;

    return Dialog(
      backgroundColor: AppColors.pureWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: AppColors.birch),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.goldPale,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.public_rounded,
                        color: AppColors.goldDeep, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Region & Currency Update',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'New global markets & multi-currency support',
                          style: GoogleFonts.ibmPlexSans(
                              fontSize: 12, color: AppColors.ink4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'YOUR COUNTRY',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.ink4,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showCountryPicker,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.imperialGold, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Text(_countryFlag(_selectedCountry),
                          style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              countryName,
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              'Tap to search and pick country',
                              style: GoogleFonts.ibmPlexSans(
                                  fontSize: 11, color: AppColors.ink4),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_drop_down_circle_outlined,
                          color: AppColors.imperialGold, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: popularCodes.map((code) {
                  final isSelected = _selectedCountry == code;
                  return ChoiceChip(
                    label: Text('${_countryFlag(code)} $code'),
                    selected: isSelected,
                    selectedColor: AppColors.imperialGold,
                    backgroundColor: AppColors.cream,
                    labelStyle: GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Colors.white : AppColors.ink,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.imperialGold
                            : AppColors.birch,
                      ),
                    ),
                    onSelected: (_) => _onCountrySelected(code),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text(
                'PREFERRED DISPLAY CURRENCY',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.ink4,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                children: Currency.values.map((c) {
                  final isSelected = _selectedCurrency == c;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCurrency = c),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.goldPale.withValues(alpha: 0.4)
                            : AppColors.cream,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.imperialGold
                              : AppColors.birch,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.imperialGold
                                  : AppColors.birch.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              c.symbol.trim(),
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.label,
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                  ),
                                ),
                                Text(
                                  c.subtitle,
                                  style: GoogleFonts.ibmPlexSans(
                                      fontSize: 11, color: AppColors.ink4),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle,
                                color: AppColors.imperialGold, size: 20),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.imperialGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'Confirm & Start Trading',
                          style: GoogleFonts.ibmPlexSans(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
