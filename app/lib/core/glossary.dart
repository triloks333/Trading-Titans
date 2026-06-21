/// Plain-English glossary of trading terms shown to beginners via inline
/// tooltips and the full Glossary screen. Definitions intentionally avoid
/// jargon and use concrete Indian-market examples.
class GlossaryTerm {
  final String term;
  final String definition;
  final String example;

  const GlossaryTerm({
    required this.term,
    required this.definition,
    required this.example,
  });
}

/// Lookup keys are lower-cased term names so callers can do a simple
/// case-insensitive fetch (e.g. Glossary.of('margin')).
class Glossary {
  Glossary._();

  static const List<GlossaryTerm> terms = [
    GlossaryTerm(
      term: 'Margin',
      definition:
          'The amount of cash blocked from your balance to hold a futures or '
          'short-option position. You do not pay the full value, only this '
          'deposit, and it is released when you exit.',
      example:
          'A futures trade worth ₹5,00,000 might block ~₹75,000 as margin '
          'instead of the full amount.',
    ),
    GlossaryTerm(
      term: 'Lot',
      definition:
          'Futures & options are bought in fixed bundles called lots, not '
          'single units. You always trade in whole lots.',
      example: '1 lot of NIFTY = 50 units. Buying 2 lots = 100 units.',
    ),
    GlossaryTerm(
      term: 'Lot Size',
      definition:
          'The number of units in one lot. It is fixed by the exchange and '
          'differs per stock or index.',
      example: 'NIFTY lot size is 50; many stocks have their own lot sizes.',
    ),
    GlossaryTerm(
      term: 'Strike Price',
      definition:
          'The fixed price at which an option lets you buy (Call) or sell '
          '(Put) the underlying. You pick a strike when trading options.',
      example:
          'A NIFTY 22,000 Call gives you the right to buy NIFTY at 22,000.',
    ),
    GlossaryTerm(
      term: 'Premium',
      definition:
          'The price you pay to buy one unit of an option. Total cost = '
          'premium × lot size × number of lots.',
      example: 'Premium ₹120 × lot size 50 = ₹6,000 to buy 1 lot.',
    ),
    GlossaryTerm(
      term: 'Expiry',
      definition:
          'The date an options or futures contract ends. After expiry the '
          'contract is settled and stops trading.',
      example: 'Weekly index options usually expire every Thursday.',
    ),
    GlossaryTerm(
      term: 'Call (CE)',
      definition:
          'An option that profits when the price goes UP. Buying a Call is a '
          'bet that the underlying will rise.',
      example: 'Buy a Call if you think NIFTY will go higher.',
    ),
    GlossaryTerm(
      term: 'Put (PE)',
      definition:
          'An option that profits when the price goes DOWN. Buying a Put is a '
          'bet that the underlying will fall.',
      example: 'Buy a Put if you think NIFTY will drop.',
    ),
    GlossaryTerm(
      term: 'LTP',
      definition:
          'Last Traded Price — the most recent price at which the stock or '
          'contract actually traded. It is the live price you usually see.',
      example: 'LTP ₹1,452.30 means the last trade happened at that price.',
    ),
    GlossaryTerm(
      term: 'Market Order',
      definition:
          'An order that executes immediately at the best available price. '
          'Fast, but the exact price can vary slightly.',
      example: 'Tap Buy as Market to get filled right away at the live price.',
    ),
    GlossaryTerm(
      term: 'Limit Order',
      definition:
          'An order that only executes at your chosen price or better. It '
          'waits until the market reaches your price.',
      example: 'Set a limit Buy at ₹1,400 to buy only at ₹1,400 or lower.',
    ),
    GlossaryTerm(
      term: 'Intraday',
      definition:
          'A trade meant to be opened and closed on the same day. Positions '
          'are squared off before the market closes.',
      example: 'Buy in the morning and sell before 3:30 PM the same day.',
    ),
    GlossaryTerm(
      term: 'Square Off',
      definition:
          'Closing an open position by placing the opposite trade — selling '
          'what you bought, or buying back what you sold.',
      example: 'If you bought 1 lot, you square off by selling 1 lot.',
    ),
    GlossaryTerm(
      term: 'P&L',
      definition:
          'Profit & Loss — how much you have gained or lost. Green is profit, '
          'red is loss.',
      example: 'A +₹2,000 P&L means your trades are ₹2,000 in profit.',
    ),
    GlossaryTerm(
      term: 'Position',
      definition:
          'A trade you currently have open in the market (futures or options) '
          'that you have not yet closed.',
      example: 'Holding 1 lot of NIFTY futures is an open position.',
    ),
    GlossaryTerm(
      term: 'Holdings',
      definition:
          'The stocks you currently own from your buy orders, sitting in your '
          'portfolio until you sell them.',
      example: '10 shares of a company you bought are part of your holdings.',
    ),
    GlossaryTerm(
      term: 'Brokerage',
      definition:
          'The fees and charges applied to a trade. In this app these are '
          'simulated so your practice mirrors real costs.',
      example: 'A small charge is deducted on each buy and sell.',
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
