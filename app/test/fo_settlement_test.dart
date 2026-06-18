import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F&O Charges & Settlement Mathematics Tests', () {
    late SupabaseService service;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://placeholder.supabase.co',
        anonKey: 'placeholder-key',
      );
      service = SupabaseService();
    });

    test('Case F: DP Charges Validation (Delivery Sell vs Other Trades)', () {
      // 1. Equity Buy: dp_charges must be 0
      final buyCharges = service.calculateTransactionCharges(
        instrumentType: 'EQUITY',
        side: 'buy',
        quantity: 10,
        price: 2500.0,
        isIntraday: false,
      );
      expect(buyCharges['dp_charges'], 0.0);

      // 2. Equity Delivery Sell: dp_charges must be 13.50
      final deliverySellCharges = service.calculateTransactionCharges(
        instrumentType: 'EQUITY',
        side: 'sell',
        quantity: 10,
        price: 2600.0,
        isIntraday: false,
      );
      expect(deliverySellCharges['dp_charges'], 13.50);

      // 3. Equity Intraday Sell: dp_charges must be 0
      final intradaySellCharges = service.calculateTransactionCharges(
        instrumentType: 'EQUITY',
        side: 'sell',
        quantity: 10,
        price: 2600.0,
        isIntraday: true,
      );
      expect(intradaySellCharges['dp_charges'], 0.0);
    });

    test('Case G: F&O Fee Breakdown Validation', () {
      final totalValue = 50000.0; // ₹50,000 turnover
      final charges = service.calculateTransactionCharges(
        instrumentType: 'FUTURE',
        side: 'buy',
        quantity: 1.0,
        price: totalValue,
        isIntraday: false,
      );

      // Verify the flat rates
      expect(charges['clearing_fee'], 0.10); // 50000 * 0.000002
      expect(charges['sebi_regulatory_fee'], 0.05); // 50000 * 0.000001
      expect(charges['turnover_tax'], 0.05); // 50000 * 0.000001
      
      // GST is 18% of (brokerage + exchange_charges + clearing_fee + sebi_regulatory_fee + turnover_tax)
      // brokerage (Futures default flat) = 20.00
      // exchange_charges = 50000 * 0.000019 = 0.95
      // clearing_fee = 0.10
      // sebi = 0.05
      // turnover_tax = 0.05
      // Sum = 20.00 + 0.95 + 0.10 + 0.05 + 0.05 = 21.15
      // GST = 21.15 * 0.18 = 3.807 -> rounded to 3.81
      expect(charges['gst'], 3.81);
    });

    test('Case A: Long Call Option OTM Expiry math', () {
      // Entry: Buy 1 lot (50 qty) NIFTY CE at ₹10
      const qty = 50.0;
      const entryPrice = 10.0;
      const premiumPaid = entryPrice * qty; // ₹500
      
      // Expiry OTM: spot <= strike, intrinsic = 0
      const intrinsicValue = 0.0;
      
      // Payoff / realized P&L = (intrinsicValue - avgPrice) * qty
      final settlementPnl = (intrinsicValue - entryPrice) * qty;
      expect(settlementPnl, -500.0);
      
      // Wallet change: credit intrinsic value * qty
      final walletChange = intrinsicValue * qty;
      expect(walletChange, 0.0);
      
      // Lifetime impact: entry (debit ₹500) + expiry (credit 0) = net loss ₹500
      expect(-premiumPaid + walletChange, -500.0);
    });

    test('Case B: Long Call Option ITM Expiry math', () {
      // Entry: Buy 1 lot (50 qty) NIFTY CE at ₹10
      const qty = 50.0;
      const entryPrice = 10.0;
      const premiumPaid = entryPrice * qty; // ₹500
      
      // Expiry ITM: spot = 23050, strike = 23000 -> intrinsic = 50
      const intrinsicValue = 50.0;
      
      // Payoff / realized P&L = (intrinsic - avgPrice) * qty
      final settlementPnl = (intrinsicValue - entryPrice) * qty;
      expect(settlementPnl, 2000.0);
      
      // Wallet change: credit intrinsic value * qty
      final walletChange = intrinsicValue * qty;
      expect(walletChange, 2500.0);
      
      // Lifetime impact: entry (debit ₹500) + expiry (credit ₹2500) = net profit ₹2000
      expect(-premiumPaid + walletChange, 2000.0);
    });

    test('Case C: Short Option OTM Expiry math', () {
      // Entry: Write 1 lot (50 qty) CE at ₹10
      const qty = 50.0;
      const entryPrice = 10.0;
      const blockedMargin = entryPrice * qty * 0.15; // ₹75
      const premiumReceived = entryPrice * qty; // ₹500
      
      // Net Entry Change: Credit ₹425 (premium - marginBlocked)
      final netEntryChange = premiumReceived - blockedMargin;
      expect(netEntryChange, 425.0);

      // Expiry OTM: intrinsic = 0
      const intrinsicValue = 0.0;

      // Realized P&L = (avgPrice - intrinsic) * qty
      final settlementPnl = (entryPrice - intrinsicValue) * qty;
      expect(settlementPnl, 500.0);

      // Wallet change at expiry: release blocked margin and pay intrinsic
      final walletChange = blockedMargin - (intrinsicValue * qty);
      expect(walletChange, 75.0);

      // Lifetime impact: entry credit (₹425) + expiry release (₹75) = net profit ₹500
      expect(netEntryChange + walletChange, 500.0);
    });

    test('Case D: Short Option ITM Expiry math', () {
      // Entry: Write 1 lot (50 qty) CE at ₹10
      const qty = 50.0;
      const entryPrice = 10.0;
      const blockedMargin = entryPrice * qty * 0.15; // ₹75
      const premiumReceived = entryPrice * qty; // ₹500
      
      // Net Entry Change: Credit ₹425 (premium - marginBlocked)
      final netEntryChange = premiumReceived - blockedMargin;
      expect(netEntryChange, 425.0);

      // Expiry ITM: spot = 23015, strike = 23000 -> intrinsic = 15
      const intrinsicValue = 15.0;

      // Realized P&L = (avgPrice - intrinsic) * qty
      final settlementPnl = (entryPrice - intrinsicValue) * qty;
      expect(settlementPnl, -250.0);

      // Wallet change at expiry: release blocked margin and pay intrinsic
      final walletChange = blockedMargin - (intrinsicValue * qty);
      expect(walletChange, -675.0); // 75 - (15 * 50) = 75 - 750 = -675

      // Lifetime impact: entry credit (₹425) + expiry change (debit ₹675) = net loss ₹250
      expect(netEntryChange + walletChange, -250.0);
    });
  });
}
