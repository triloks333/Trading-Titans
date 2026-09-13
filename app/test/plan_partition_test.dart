// Feeds the REAL /rest/v1/plan_catalogue payload through the parser and the
// split the plans screen does, because "only the top-ups are showing" is exactly
// what a wrong `kind` comparison or a bad cast would look like.
//
// The JSON below is copied verbatim from a live request against production, so
// the types are the ones the device actually receives rather than the ones a
// hand-written fixture would flatter us with.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/plan_service.dart';

const String _liveResponse = '''
[{"sku":"topup_boost","tier":"topup","kind":"one_time","title":"Boost","price_paise":19900,"billing_interval":null,"cash_grant":100000,"monthly_stipend":0,"razorpay_plan_id":null,"is_active":true,"sort_order":10},
 {"sku":"topup_plus","tier":"topup","kind":"one_time","title":"Plus","price_paise":59900,"billing_interval":null,"cash_grant":500000,"monthly_stipend":0,"razorpay_plan_id":null,"is_active":true,"sort_order":20},
 {"sku":"topup_max","tier":"topup","kind":"one_time","title":"Max","price_paise":99900,"billing_interval":null,"cash_grant":1000000,"monthly_stipend":0,"razorpay_plan_id":null,"is_active":true,"sort_order":30},
 {"sku":"pro_monthly","tier":"pro","kind":"subscription","title":"Pro Monthly","price_paise":14900,"billing_interval":"monthly","cash_grant":0,"monthly_stipend":50000,"razorpay_plan_id":"plan_A","is_active":true,"sort_order":40},
 {"sku":"pro_annual","tier":"pro","kind":"subscription","title":"Pro Annual","price_paise":119900,"billing_interval":"annual","cash_grant":0,"monthly_stipend":50000,"razorpay_plan_id":"plan_B","is_active":true,"sort_order":50},
 {"sku":"titan_monthly","tier":"titan","kind":"subscription","title":"Titan Monthly","price_paise":79900,"billing_interval":"monthly","cash_grant":0,"monthly_stipend":500000,"razorpay_plan_id":"plan_C","is_active":true,"sort_order":60},
 {"sku":"titan_annual","tier":"titan","kind":"subscription","title":"Titan Annual","price_paise":599900,"billing_interval":"annual","cash_grant":0,"monthly_stipend":500000,"razorpay_plan_id":"plan_D","is_active":true,"sort_order":70}]
''';

List<PlanOption> parseAll() => (jsonDecode(_liveResponse) as List<dynamic>)
    .map((e) => PlanOption.fromJson(Map<String, dynamic>.from(e as Map)))
    .toList();

void main() {
  test('every live row parses without throwing', () {
    final all = parseAll();
    expect(all.length, 7);
  });

  test('the screen split yields four plans and three top-ups', () {
    final all = parseAll();
    // The exact two lines the plans screen uses.
    final subscriptions = all.where((p) => p.isSubscription).toList();
    final topups = all.where((p) => !p.isSubscription).toList();

    expect(
      subscriptions.map((p) => p.sku).toList(),
      ['pro_monthly', 'pro_annual', 'titan_monthly', 'titan_annual'],
      reason: 'subscriptions vanishing here is the reported bug',
    );
    expect(topups.map((p) => p.sku).toList(),
        ['topup_boost', 'topup_plus', 'topup_max']);
  });

  test('subscription rows carry the fields their card renders', () {
    final pro = parseAll().firstWhere((p) => p.sku == 'pro_monthly');
    expect(pro.isSubscription, isTrue);
    expect(pro.priceRupees, 149.0);
    expect(pro.monthlyStipend, 50000);
    expect(pro.billingInterval, 'monthly');
    expect(pro.tier, 'pro');
  });
}
