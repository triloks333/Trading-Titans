int getOptionLotSize(String symbol) {
  final cleanSym = symbol.toUpperCase().trim();
  
  // Extract underlying symbol if it is an option ticker (e.g. ICICIBANK-2026-05-28-1250-CE)
  final underlying = cleanSym.split('-').first;

  const lotSizes = {
    'NIFTY': 50,
    'BANKNIFTY': 15,
    'RELIANCE': 250,
    'TCS': 175,
    'HDFCBANK': 550,
    'INFY': 400,
    'ICICIBANK': 700,
    'HINDUNILVR': 300,
    'ITC': 1600,
    'SBIN': 1500,
    'BHARTIARTL': 950,
    'KOTAKBANK': 400,
    'LT': 300,
    'AXISBANK': 625,
    'ASIANPAINT': 200,
    'MARUTI': 100,
    'BAJFINANCE': 125,
    'WIPRO': 1500,
    'HCLTECH': 700,
    'ULTRACEMCO': 100,
    'TITAN': 375,
    'SUNPHARMA': 700,
    'TATAMOTORS': 1425,
    'TMCV': 1425,
    'TMPV': 1425,
    'ADANIENT': 250,
    'NTPC': 3000,
  };

  return lotSizes[underlying] ?? 100; // Default to 100 if not found
}
