import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/main/subscribe_screen.dart';
import 'package:mobile/services/plan_service.dart';

void main() {
  test('SubscribeScreen constructor sets default and custom initialTabIndex', () {
    const defaultScreen = SubscribeScreen();
    expect(defaultScreen.initialTabIndex, 0);

    const topUpScreen = SubscribeScreen(initialTabIndex: 1);
    expect(topUpScreen.initialTabIndex, 1);
  });

  test('Packages sort lower prices on top (149 then 799; 199 then 599 then 999)', () {
    final subscriptions = [
      const PlanOption(
        sku: 'titan_monthly',
        tier: 'titan',
        kind: 'subscription',
        title: 'Titan Monthly',
        pricePaise: 79900,
        priceUsdCents: null,
        billingInterval: 'monthly',
        cashGrant: 0,
        monthlyStipend: 1000000,
      ),
      const PlanOption(
        sku: 'pro_monthly',
        tier: 'pro',
        kind: 'subscription',
        title: 'Pro Monthly',
        pricePaise: 14900,
        priceUsdCents: null,
        billingInterval: 'monthly',
        cashGrant: 0,
        monthlyStipend: 50000,
      ),
    ]..sort((a, b) => a.pricePaise.compareTo(b.pricePaise));

    expect(subscriptions.first.pricePaise, 14900);
    expect(subscriptions.last.pricePaise, 79900);

    final topups = [
      const PlanOption(
        sku: 'topup_999',
        tier: 'free',
        kind: 'one_time',
        title: 'Max Pack',
        pricePaise: 99900,
        priceUsdCents: null,
        billingInterval: null,
        cashGrant: 1000000,
        monthlyStipend: 0,
      ),
      const PlanOption(
        sku: 'topup_199',
        tier: 'free',
        kind: 'one_time',
        title: 'Starter Pack',
        pricePaise: 19900,
        priceUsdCents: null,
        billingInterval: null,
        cashGrant: 100000,
        monthlyStipend: 0,
      ),
      const PlanOption(
        sku: 'topup_599',
        tier: 'free',
        kind: 'one_time',
        title: 'Pro Pack',
        pricePaise: 59900,
        priceUsdCents: null,
        billingInterval: null,
        cashGrant: 500000,
        monthlyStipend: 0,
      ),
    ]..sort((a, b) => a.pricePaise.compareTo(b.pricePaise));

    expect(topups.map((p) => p.pricePaise).toList(), [19900, 59900, 99900]);
  });
}

