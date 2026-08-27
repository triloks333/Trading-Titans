/// The Indian equity session, in one place.
///
/// REPORTED AS: "stock market closing ... not updated with the current stock
/// market".
///
/// NSE and BSE trade 09:15-15:30 IST. The window was duplicated in five edge
/// functions and four of them closed at 15:15, a quarter of an hour early:
///
///   refresh-quotes           minutes < 915   quotes stopped updating at 15:15
///   place-order              minutes < 915   orders routed to pending at 15:15
///   evaluate-price-alerts    minutes < 915   alerts stopped firing at 15:15
///   execute-pending-orders   minutes < 915   fills stopped at 15:15
///   market-status            <= 930          correct, and it is the one the app
///                                            shows the user
///
/// So the app announced "Market Open — 9:15 AM to 3:30 PM IST" while nothing
/// could actually trade for the last fifteen minutes of every session. The
/// Flutter client had the same 915 cutoff even though its own `sessionLabel`
/// advertised 3:30 PM.
///
/// ponytail: one shared helper instead of a sixth copy. Deliberately keeps the
/// existing "weekends only" behaviour -- there is still no exchange holiday
/// calendar, so on Diwali this reports open and a market order fills at the last
/// published price. The ceiling is holidays; the upgrade path is a
/// `market_holidays` table keyed on (market, date) checked here, which then fixes
/// every caller at once. That is exactly the property the old copy-paste lacked.

/// 09:15 IST expressed as minutes past IST midnight.
export const IST_OPEN_MINUTES = 9 * 60 + 15; // 555

/// 15:30 IST expressed as minutes past IST midnight. The session is half-open,
/// [open, close), so 15:30:00 itself is closed -- matching the exchange, where
/// the last trade prints before the closing bell.
export const IST_CLOSE_MINUTES = 15 * 60 + 30; // 930

/// Now, shifted so its UTC fields read as IST wall-clock time.
export function istNow(at: Date = new Date()): Date {
  return new Date(at.getTime() + 5.5 * 3600 * 1000);
}

/// True during the Indian equity session: Mon-Fri, 09:15 (inclusive) to 15:30
/// (exclusive) IST.
export function isStockOpen(at: Date = new Date()): boolean {
  const ist = istNow(at);
  const day = ist.getUTCDay();
  if (day === 0 || day === 6) return false;
  const minutes = ist.getUTCHours() * 60 + ist.getUTCMinutes();
  return minutes >= IST_OPEN_MINUTES && minutes < IST_CLOSE_MINUTES;
}
