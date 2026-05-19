import { useEffect, useRef } from "react";

/**
 * Calls `fn` immediately and then every `intervalMs` while mounted.
 * Useful for polling live market data. Pass `enabled=false` to pause.
 */
export function usePolling(fn: () => void | Promise<void>, intervalMs: number, enabled = true) {
  const fnRef = useRef(fn);
  fnRef.current = fn;
  useEffect(() => {
    if (!enabled) return;
    let cancelled = false;
    const tick = async () => {
      if (cancelled) return;
      try {
        await fnRef.current();
      } catch (_) {}
    };
    tick();
    const id = setInterval(tick, intervalMs);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [intervalMs, enabled]);
}
