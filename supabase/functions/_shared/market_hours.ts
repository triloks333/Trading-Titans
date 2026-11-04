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

/// Known official NSE/BSE holidays for 2026.
export const INDIAN_HOLIDAYS_2026 = new Set([
  "2026-01-26", // Republic Day
  "2026-03-03", // Holi
  "2026-03-26", // Shri Ram Navami
  "2026-03-31", // Shri Mahavir Jayanti
  "2026-04-03", // Good Friday
  "2026-04-14", // Dr. Baba Saheb Ambedkar Jayanti
  "2026-05-01", // Maharashtra Day
  "2026-05-28", // Bakri Id
  "2026-06-26", // Muharram
  "2026-09-14", // Ganesh Chaturthi
  "2026-10-02", // Mahatma Gandhi Jayanti
  "2026-10-20", // Dussehra (Vijayadashami)
  "2026-11-10", // Diwali-Balipratipada
  "2026-11-24", // Prakash Gurpurb Sri Guru Nanak Dev
  "2026-12-25", // Christmas
]);

export function isIndianStockHoliday(at: Date = new Date()): boolean {
  const ist = istNow(at);
  const y = ist.getUTCFullYear();
  const m = String(ist.getUTCMonth() + 1).padStart(2, "0");
  const d = String(ist.getUTCDate()).padStart(2, "0");
  return INDIAN_HOLIDAYS_2026.has(`${y}-${m}-${d}`);
}

/// One-off sessions outside the normal week (Diwali Muhurat trading), as ISO
/// instants, half-open [start, end). Mirror of public.market_special_sessions,
/// which the app reads; add the window to both once NSE publishes it.
export const SPECIAL_SESSIONS: { name: string; start: string; end: string }[] = [];

export function isSpecialSession(at: Date = new Date(), sessions = SPECIAL_SESSIONS): boolean {
  const t = at.getTime();
  return sessions.some((s) => t >= Date.parse(s.start) && t < Date.parse(s.end));
}

/// True during the Indian equity session: Mon-Fri, 09:15 (inclusive) to 15:30
/// (exclusive) IST, and not on an exchange trading holiday; or during a special
/// session such as Muhurat trading.
export function isStockOpen(at: Date = new Date()): boolean {
  if (isSpecialSession(at)) return true;
  const ist = istNow(at);
  const day = ist.getUTCDay();
  if (day === 0 || day === 6) return false;
  if (isIndianStockHoliday(at)) return false;
  const minutes = ist.getUTCHours() * 60 + ist.getUTCMinutes();
  return minutes >= IST_OPEN_MINUTES && minutes < IST_CLOSE_MINUTES;
}
