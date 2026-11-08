export 'intel_ids.g.dart';
import 'intel_ids.g.dart';

/// `OrderEntryScreen` / `_OrderEntryScreenState` / `order_entry_screen` → `order_entry_screen`.
String screenSlug(String raw) {
  var s = raw.replaceAll(RegExp(r'<.*>'), '').replaceAll(RegExp(r'^_+'), '').replaceAll(RegExp(r'State$'), '');
  s = s.replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => '_${m[1]}').toLowerCase();
  return s.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
}

const _symbolAliases = {
  'nifty 50': 'nifty', '^nsei': 'nifty', 'nifty50': 'nifty',
  'nifty bank': 'banknifty', '^nsebank': 'banknifty', 'bank nifty': 'banknifty',
  'nifty fin service': 'finnifty', 'nifty midcap select': 'midcpnifty',
  'zomato': 'eternal', 'gold': 'gold_crude_mcx', 'crudeoil': 'gold_crude_mcx', 'crude': 'gold_crude_mcx',
  'matic': 'pol',
};

// Longest first so BANKNIFTY... never matches NIFTY.
final _derivPrefixes = [...kIntelSymbols]..sort((a, b) => b.length.compareTo(a.length));

/// Maps an app symbol (`RELIANCE.NS`, `BTCUSDT`, `NIFTY25NOV24000CE`, `ENI.MI`)
/// to the catalogue slug, or null for symbols outside the 65 tracked ones.
String? symbolSlug(String raw) {
  var s = raw.trim().toLowerCase();
  if (_symbolAliases.containsKey(s)) return _symbolAliases[s];
  if (s.endsWith('.ka') || s.endsWith('.mi')) s = s.replaceAll('.', '_');
  s = s.replaceAll(RegExp(r'\.(ns|bo)$'), '').replaceAll(RegExp(r'(-usd|-inr|usdt|inr)$'), '');
  if (_symbolAliases.containsKey(s)) return _symbolAliases[s];
  if (kIntelSymbols.contains(s)) return s;
  // Derivatives: underlying + expiry digits + CE/PE/FUT.
  if (RegExp(r'\d').hasMatch(s) && RegExp(r'(ce|pe|fut)$').hasMatch(s)) {
    for (final p in _derivPrefixes) {
      if (s.startsWith(p) && p.length > 2) return p;
    }
  }
  return null;
}

/// Button id prefix → screen whose opens are the CTR denominator. Buttons on
/// global surfaces (nav bar, dialogs, sheets) use app opens instead (null).
const _buttonScreens = {
  'home_': 'dashboard_screen', 'trade_': 'trade_screen', 'portfolio_': 'portfolio_screen',
  'wallet_': 'wallet_screen', 'compete_': 'compete_screen', 'profile_': 'profile_screen',
  'settings_': 'settings_screen', 'order_ticket_': 'order_entry_screen', 'orders_': 'orders_screen',
  'option_chain_': 'option_chain_screen', 'option_detail_': 'option_detail_screen',
  'stock_detail_': 'stock_detail_screen', 'pro_chart_': 'fullscreen_chart_screen',
  'subscribe_': 'subscribe_screen', 'analytics_': 'analytics_screen', 'autopsy_': 'autopsy_screen',
  'challenges_': 'challenges_screen', 'chat_': 'chat_screen', 'refer_earn_': 'refer_earn_screen',
  'whatif_': 'whatif_screen',
};

String? buttonScreen(String buttonId) {
  for (final e in _buttonScreens.entries) {
    if (buttonId.startsWith(e.key)) return e.value;
  }
  return null;
}
