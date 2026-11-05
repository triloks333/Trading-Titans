/// Clean symbol for display: strips the NSE:/BSE: prefix and the -EQ/-SM/-BE/-BZ
/// series suffix, so "NSE:CUPID-EQ" reads "CUPID".
String displaySymbol(String symbol) {
  var s = symbol;
  if (s.startsWith('NSE:') || s.startsWith('BSE:')) s = s.substring(4);
  return s.replaceAll(RegExp(r'-(EQ|SM|BE|BZ)$'), '');
}
