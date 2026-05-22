import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/market_service.dart';

class WhatIfScreen extends StatefulWidget {
  const WhatIfScreen({super.key});

  @override
  State<WhatIfScreen> createState() => _WhatIfScreenState();
}

class _WhatIfScreenState extends State<WhatIfScreen> {
  String _symbol = 'RELIANCE';
  String _market = 'stock';
  String _amount = '10000';
  String _years = '3';
  bool _busy = false;
  Map<String, dynamic>? _result;

  Future<void> _runSimulation() async {
    setState(() => _busy = true);
    final amount = double.tryParse(_amount.replaceAll(',', '')) ?? 0.0;
    final years = int.tryParse(_years) ?? 1;
    final result = await MarketService.simulateWhatIf(_symbol, _market, amount, years);
    setState(() {
      _result = result;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('What-If Simulator'),
        backgroundColor: AppColors.parchment,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: AppColors.birch)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('If I had invested in… how much would I have today?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  const SizedBox(height: AppSpacing.lg),
                  Row(children: [
                    _segmentButton('stock'),
                    const SizedBox(width: AppSpacing.sm),
                    _segmentButton('crypto'),
                  ]),
                  const SizedBox(height: AppSpacing.lg),
                  _inputField('Symbol', _symbol, (value) => _symbol = value.toUpperCase()),
                  const SizedBox(height: AppSpacing.sm),
                  _inputField('Amount (₹)', _amount, (value) => _amount = value),
                  const SizedBox(height: AppSpacing.sm),
                  _inputField('Years Ago', _years, (value) => _years = value),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _runSimulation,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.imperialGold, padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: _busy
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: AppColors.pureWhite, strokeWidth: 2))
                          : const Text('Calculate', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.pureWhite)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_result != null)
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(color: AppColors.warmWhite, borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: AppColors.birch)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Result for ${_result!['symbol']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Invested ₹${(_result!['amount_invested'] as num).toStringAsFixed(0)}', style: const TextStyle(color: AppColors.ink4)),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Current value ₹${(_result!['current_value'] as num).toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
                    const SizedBox(height: AppSpacing.sm),
                    Text('P&L ${(_result!['pnl'] as num) >= 0 ? '+' : ''}₹${(_result!['pnl'] as num).toStringAsFixed(0)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: (_result!['pnl'] as num) >= 0 ? AppColors.bull : AppColors.bear)),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Units held ${(_result!['units'] as num).toStringAsFixed(4)}', style: const TextStyle(color: AppColors.ink4)),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Simulated purchase price ₹${(_result!['purchase_price'] as num).toStringAsFixed(2)}', style: const TextStyle(color: AppColors.ink4)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _segmentButton(String value) {
    final selected = _market == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _market = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.pureWhite : AppColors.cream,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.birch),
          ),
          child: Text(value.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(color: selected ? AppColors.ink : AppColors.ink4, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _inputField(String label, String value, void Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.ink3)),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          onChanged: onChanged,
          controller: TextEditingController(text: value),
          decoration: InputDecoration(
            hintText: label,
            filled: true,
            fillColor: AppColors.cream,
            border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
          ),
        ),
      ],
    );
  }
}
