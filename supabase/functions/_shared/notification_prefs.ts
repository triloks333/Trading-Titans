// Which Settings → Notifications switch governs an action_type, or null when
// the type always sends (chat has its own mute; account and broadcast always go).
// Keep in step with migrations/20261105020000_notification_preferences.sql.
export function prefKeyFor(t: string | null | undefined): "price" | "orders" | "league" | "news" | null {
  switch (t) {
    case "price_alert": return "price";
    case "order":
    case "order_executed":
    case "order_pending":
    case "order_failed":
    case "trade":
    case "expiry":
    case "risk_alert": return "orders";
    case "reward":
    case "league": return "league";
    case "news": return "news";
    default: return null;
  }
}
