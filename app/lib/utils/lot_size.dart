/// Returns the lot size for a derivative contract (futures/options).
/// Lot sizes are the same for both futures and options of the same underlying.
/// Based on NSE contract specifications (revised effective Dec 30, 2025).
int getOptionLotSize(String symbol) {
  var cleanSym = symbol.toUpperCase().trim();
  
  // Strip Fyers exchange prefix if present
  if (cleanSym.startsWith('NSE:')) {
    cleanSym = cleanSym.substring(4);
  } else if (cleanSym.startsWith('BSE:')) {
    cleanSym = cleanSym.substring(4);
  }

  // ── Index lot sizes (post SEBI Dec 2025 revision) ──
  // Contract value target: ₹15-20 lakh range
  const indexLotSizes = {
    'NIFTY': 65,
    'NIFTY50': 65,
    'BANKNIFTY': 30,
    'NIFTYBANK': 30,
    'FINNIFTY': 60,
    'MIDCPNIFTY': 120,
    'SENSEX': 20,
    'BANKEX': 30,
  };

  // ── Stock lot sizes (NSE F&O segment) ──
  // These are periodically revised by NSE based on SEBI guidelines
  const stockLotSizes = {
    'RELIANCE': 250,
    'TCS': 300,
    'HDFCBANK': 550,
    'INFY': 400,
    'ICICIBANK': 700,
    'HINDUNILVR': 300,
    'ITC': 1600,
    'SBIN': 1375,
    'BHARTIARTL': 475,
    'KOTAKBANK': 400,
    'LT': 175,
    'AXISBANK': 1200,
    'ASIANPAINT': 200,
    'MARUTI': 50,
    'BAJFINANCE': 125,
    'WIPRO': 3000,
    'HCLTECH': 350,
    'ULTRACEMCO': 50,
    'TITAN': 175,
    'SUNPHARMA': 350,
    'TATAMOTORS': 800,
    'ADANIENT': 309,
    'NTPC': 1500,
    'TATASTEEL': 1100,
    'POWERGRID': 2700,
    'ONGC': 1925,
    'COALINDIA': 1050,
    'JSWSTEEL': 675,
    'DRREDDY': 125,
    'CIPLA': 650,
    'DIVISLAB': 200,
    'BAJAJ-AUTO': 250,
    'BAJAJFINSV': 500,
    'EICHERMOT': 175,
    'TECHM': 600,
    'HEROMOTOCO': 200,
    'BPCL': 1800,
    'GRASIM': 350,
    'TATACONSUM': 600,
    'M&M': 350,
    'NESTLEIND': 50,
    'ETERNAL': 1200,   // formerly Zomato
    'ZOMATO': 1200,
    'INDUSINDBK': 900,
    'HINDALCO': 1075,
    'VEDL': 1550,
    'APOLLOHOSP': 125,
    'SBILIFE': 550,
    'HDFCLIFE': 1100,
    'SHRIRAMFIN': 200,
    'PNB': 6000,
    'BANKBARODA': 2700,
    'IOC': 4500,
    'GAIL': 3050,
    'TRENT': 100,
    'ABB': 125,
    'SIEMENS': 100,
    'HAL': 175,
    'BEL': 2750,
    'PEL': 375,
    'PIIND': 250,
    'LTIM': 150,
    'PERSISTENT': 125,
    'COFORGE': 75,
    'MPHASIS': 325,
  };

  // Combine all known symbols and sort by length descending to match longest prefix first
  final allKnownUnderlyings = [
    ...indexLotSizes.keys,
    ...stockLotSizes.keys,
  ]..sort((a, b) => b.length.compareTo(a.length));

  for (final key in allKnownUnderlyings) {
    if (cleanSym.startsWith(key)) {
      return indexLotSizes[key] ?? stockLotSizes[key] ?? 100;
    }
  }

  // Fallback to split format
  final underlying = cleanSym.split('-').first.split(' ').first;

  return indexLotSizes[underlying]
      ?? stockLotSizes[underlying]
      ?? 100; // Default to 100 if not in the list
}
