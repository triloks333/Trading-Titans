/// Plain-English glossary of trading terms shown to beginners via inline
/// tooltips and the full Glossary screen. Definitions intentionally avoid
/// jargon and use concrete Indian-market examples.
class GlossaryTerm {
  final String term;
  final String definition;
  final String example;
  final String category;

  const GlossaryTerm({
    required this.term,
    required this.definition,
    required this.example,
    this.category = 'Basics',
  });
}

/// Lookup keys are lower-cased term names so callers can do a simple
/// case-insensitive fetch (e.g. Glossary.of('margin')).
class Glossary {
  Glossary._();

  static const List<String> categories = [
    'All',
    'Basics',
    'Options',
    'Greeks',
    'Futures & Margin',
    'Orders & Risk',
  ];

  static const List<GlossaryTerm> terms = [
    // -------------------------------------------------------------
    // BASICS
    // -------------------------------------------------------------
    GlossaryTerm(
      term: 'LTP',
      definition:
          'Last Traded Price — the most recent price at which the stock or '
          'contract actually traded. It is the live price you usually see.',
      example: 'LTP ₹1,452.30 means the last trade happened at that price.',
      category: 'Basics',
    ),
    GlossaryTerm(
      term: 'Holdings',
      definition:
          'The stocks you currently own from your buy orders, sitting in your '
          'portfolio until you sell them.',
      example: '10 shares of a company you bought are part of your holdings.',
      category: 'Basics',
    ),
    GlossaryTerm(
      term: 'Position',
      definition:
          'A trade you currently have open in the market (futures or options) '
          'that you have not yet closed.',
      example: 'Holding 1 lot of NIFTY futures is an open position.',
      category: 'Basics',
    ),
    GlossaryTerm(
      term: 'Intraday',
      definition:
          'A trade meant to be opened and closed on the same day. Positions '
          'are squared off before the market closes.',
      example: 'Buy in the morning and sell before 3:30 PM the same day.',
      category: 'Basics',
    ),
    GlossaryTerm(
      term: 'Square Off',
      definition:
          'Closing an open position by placing the opposite trade — selling '
          'what you bought, or buying back what you sold.',
      example: 'If you bought 1 lot, you square off by selling 1 lot.',
      category: 'Basics',
    ),
    GlossaryTerm(
      term: 'Brokerage',
      definition:
          'The fees and charges applied to a trade. In this app these are '
          'simulated so your practice mirrors real costs.',
      example: 'A small charge is deducted on each buy and sell.',
      category: 'Basics',
    ),

    // -------------------------------------------------------------
    // OPTIONS
    // -------------------------------------------------------------
    GlossaryTerm(
      term: 'Call (CE)',
      definition:
          'An option that profits when the price goes UP. Buying a Call is a '
          'bet that the underlying will rise.',
      example: 'Buy a Call if you think NIFTY will go higher.',
      category: 'Options',
    ),
    GlossaryTerm(
      term: 'Put (PE)',
      definition:
          'An option that profits when the price goes DOWN. Buying a Put is a '
          'bet that the underlying will fall.',
      example: 'Buy a Put if you think NIFTY will drop.',
      category: 'Options',
    ),
    GlossaryTerm(
      term: 'Strike Price',
      definition:
          'The fixed price at which an option lets you buy (Call) or sell '
          '(Put) the underlying. You pick a strike when trading options.',
      example:
          'A NIFTY 22,000 Call gives you the right to buy NIFTY at 22,000.',
      category: 'Options',
    ),
    GlossaryTerm(
      term: 'Premium',
      definition:
          'The price you pay to buy one unit of an option. Total cost = '
          'premium × lot size × number of lots.',
      example: 'Premium ₹120 × lot size 50 = ₹6,00,000 to buy 1 lot.',
      category: 'Options',
    ),
    GlossaryTerm(
      term: 'Expiry',
      definition:
          'The date an options or futures contract ends. After expiry the '
          'contract is settled and stops trading.',
      example: 'Weekly index options usually expire every Thursday.',
      category: 'Options',
    ),
    GlossaryTerm(
      term: 'ITM (In the Money)',
      definition:
          'An option contract with positive intrinsic value. For a Call, the '
          'strike is below the market price; for a Put, the strike is above.',
      example: 'If NIFTY is at 22,500, a 22,300 Call is ITM by ₹200.',
      category: 'Options',
    ),
    GlossaryTerm(
      term: 'OTM (Out of the Money)',
      definition:
          'An option contract with zero intrinsic value. It contains only time '
          'value and expires worthless if the strike is not crossed.',
      example: 'If NIFTY is at 22,500, a 22,800 Call is OTM.',
      category: 'Options',
    ),
    GlossaryTerm(
      term: 'ATM (At the Money)',
      definition:
          'An option whose strike price is identical or closest to the '
          'current spot price of the underlying index or stock.',
      example: 'If NIFTY is at 22,508, the 22,500 Call and Put are ATM.',
      category: 'Options',
    ),
    GlossaryTerm(
      term: 'Intrinsic Value',
      definition:
          'The built-in financial worth of an in-the-money option if '
          'exercised right now. Out-of-the-money options have zero intrinsic value.',
      example: 'For a 22,000 Call when NIFTY is 22,250, intrinsic value is ₹250.',
      category: 'Options',
    ),
    GlossaryTerm(
      term: 'Time Value',
      definition:
          'The portion of an option premium above its intrinsic value, '
          'reflecting the probability of favorable moves before expiry.',
      example: 'If premium is ₹320 and intrinsic value is ₹250, time value is ₹70.',
      category: 'Options',
    ),

    // -------------------------------------------------------------
    // GREEKS
    // -------------------------------------------------------------
    GlossaryTerm(
      term: 'Delta',
      definition:
          'Measures how much the option price moves for every ₹1 change in '
          'the underlying asset. Ranges from 0 to 1 for Calls, 0 to -1 for Puts.',
      example: 'A Call with 0.50 Delta gains ₹5 if the underlying rises by ₹10.',
      category: 'Greeks',
    ),
    GlossaryTerm(
      term: 'Theta',
      definition:
          'Measures time decay — the daily loss in an option’s premium as '
          'expiry draws closer, even if the stock price does not move.',
      example: 'A Theta of -12 means the option decays by ₹12 every single day.',
      category: 'Greeks',
    ),
    GlossaryTerm(
      term: 'Gamma',
      definition:
          'Measures the rate of change of Delta for a ₹1 move in the underlying. '
          'Shows how fast your option speeds up during sharp moves.',
      example: 'High Gamma near expiry creates explosive explosive price moves.',
      category: 'Greeks',
    ),
    GlossaryTerm(
      term: 'Vega',
      definition:
          'Measures option sensitivity to changes in Implied Volatility. '
          'Premiums rise when volatility jumps and deflate when volatility crashes.',
      example: 'A Vega of 8.5 means a 1% jump in IV adds ₹8.50 to the premium.',
      category: 'Greeks',
    ),
    GlossaryTerm(
      term: 'IV (Implied Volatility)',
      definition:
          'The market’s expectation of future price swings. High IV makes '
          'options expensive; low IV makes options cheap.',
      example: 'IV typically spikes before major election results or earnings.',
      category: 'Greeks',
    ),

    // -------------------------------------------------------------
    // FUTURES & MARGIN
    // -------------------------------------------------------------
    GlossaryTerm(
      term: 'Margin',
      definition:
          'The amount of cash blocked from your balance to hold a futures or '
          'short-option position. Released back to you upon exit.',
      example:
          'A futures trade worth ₹5,00,000 might block ~₹75,000 as margin '
          'instead of the full amount.',
      category: 'Futures & Margin',
    ),
    GlossaryTerm(
      term: 'Lot',
      definition:
          'Futures & options are bought in fixed bundles called lots, not '
          'single units. You always trade in whole lots.',
      example: '1 lot of NIFTY = 50 units. Buying 2 lots = 100 units.',
      category: 'Futures & Margin',
    ),
    GlossaryTerm(
      term: 'Lot Size',
      definition:
          'The number of units in one lot. It is fixed by the exchange and '
          'differs per stock or index.',
      example: 'NIFTY lot size is 50; many stocks have their own lot sizes.',
      category: 'Futures & Margin',
    ),
    GlossaryTerm(
      term: 'Open Interest (OI)',
      definition:
          'The total number of open/active derivative contracts currently held '
          'by market participants. Helps identify major support and resistance.',
      example: 'Heavy OI build-up at 23,000 Call indicates tough resistance at 23,000.',
      category: 'Futures & Margin',
    ),

    // -------------------------------------------------------------
    // ORDERS & RISK
    // -------------------------------------------------------------
    GlossaryTerm(
      term: 'Market Order',
      definition:
          'An order that executes immediately at the best available price. '
          'Fast, but the exact price can vary slightly.',
      example: 'Tap Buy as Market to get filled right away at the live price.',
      category: 'Orders & Risk',
    ),
    GlossaryTerm(
      term: 'Limit Order',
      definition:
          'An order that only executes at your chosen price or better. It '
          'waits until the market reaches your price.',
      example: 'Set a limit Buy at ₹1,400 to buy only at ₹1,400 or lower.',
      category: 'Orders & Risk',
    ),
    GlossaryTerm(
      term: 'Stop Loss (SL)',
      definition:
          'A defensive order placed to automatically exit your trade if the '
          'market reaches a threshold, capping your maximum loss.',
      example: 'Buying at ₹500 with a Stop Loss at ₹485 strictly limits loss to ₹15.',
      category: 'Orders & Risk',
    ),
    GlossaryTerm(
      term: 'Trailing Stop Loss (TSL)',
      definition:
          'A moving stop loss that automatically trails upward behind a rising '
          'market price to protect accumulated profits.',
      example: 'When your stock climbs from ₹500 to ₹550, a 5% TSL moves up to ₹522.50.',
      category: 'Orders & Risk',
    ),
    GlossaryTerm(
      term: 'Target',
      definition:
          'The pre-calculated price at which you intend to exit and lock in '
          'profits based on your risk-to-reward ratio.',
      example: 'Risking ₹10 with a target of ₹30 gives a favorable 1:3 ratio.',
      category: 'Orders & Risk',
    ),
    GlossaryTerm(
      term: 'P&L',
      definition:
          'Profit & Loss — how much you have gained or lost. Green is profit, '
          'red is loss.',
      example: 'A +₹2,000 P&L means your trades are ₹2,000 in profit.',
      category: 'Orders & Risk',
    ),
    GlossaryTerm(
      term: 'Slippage',
      definition:
          'The difference between expected trade execution price and actual '
          'filled price due to market speed or volatility.',
      example: 'Submitting a buy at ₹100 that fills at ₹100.25 has ₹0.25 slippage.',
      category: 'Orders & Risk',
    ),
  ];

  /// Case-insensitive lookup. Returns null when the term is unknown.
  static GlossaryTerm? of(String term) {
    final key = term.trim().toLowerCase();
    for (final t in terms) {
      if (t.term.toLowerCase() == key) return t;
    }
    return null;
  }
}
