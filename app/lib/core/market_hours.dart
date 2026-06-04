class MarketHours {
  static bool isOpen(String market) {
    if (market == 'crypto') return true;

    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final minutes = now.hour * 60 + now.minute;
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) return false;
    return minutes >= 555 && minutes < 915;
  }

  static String statusText(String market) {
    if (market == 'crypto') return '24/7 Market';
    if (isOpen(market)) return 'Market Open';
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) return 'Weekend Closed';
    return 'Opens at 9:15 AM IST';
  }

  static String nextOpen(String market) {
    if (market == 'crypto' || isOpen(market)) return '';
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final day = now.weekday;
    if (day == DateTime.saturday || day == DateTime.sunday) return 'Opens Monday 9:15 AM IST';
    return 'Opens at 9:15 AM IST';
  }
}
