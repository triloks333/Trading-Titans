import React, { useCallback, useEffect, useState } from "react";
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  ActivityIndicator,
  Modal,
  TextInput,
  KeyboardAvoidingView,
  Platform,
  Alert,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useLocalSearchParams, useRouter } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, shadow, formatINR, formatPct } from "@/src/theme";
import { api, Quote, HistoryPoint } from "@/src/api/client";
import PriceChart from "@/src/components/PriceChart";
import { useAuth } from "@/src/context/AuthContext";

const RANGES = [
  { key: "1d", label: "1D" },
  { key: "5d", label: "1W" },
  { key: "1mo", label: "1M" },
  { key: "3mo", label: "3M" },
  { key: "1y", label: "1Y" },
  { key: "5y", label: "5Y" },
];

export default function StockDetail() {
  const { symbol, market, name } = useLocalSearchParams<{ symbol: string; market: string; name?: string }>();
  const router = useRouter();
  const { user, refreshUser } = useAuth();
  const [quote, setQuote] = useState<Quote | null>(null);
  const [points, setPoints] = useState<HistoryPoint[]>([]);
  const [range, setRange] = useState("1mo");
  const [loadingChart, setLoadingChart] = useState(false);
  const [showOrder, setShowOrder] = useState<"buy" | "sell" | null>(null);
  const [qty, setQty] = useState("");
  const [placing, setPlacing] = useState(false);
  const [holding, setHolding] = useState<any>(null);
  const [isWatched, setIsWatched] = useState(false);

  const m = (market as string) || "stock";

  const loadQuote = useCallback(async () => {
    try {
      const q = await api.quote(symbol as string, m);
      setQuote(q);
    } catch (e) {
      console.warn("quote err", e);
    }
  }, [symbol, m]);

  const loadChart = useCallback(async (r: string) => {
    setLoadingChart(true);
    try {
      const res = await api.history(symbol as string, m, r);
      setPoints(res.points);
    } catch (e) {
      console.warn("history err", e);
      setPoints([]);
    } finally {
      setLoadingChart(false);
    }
  }, [symbol, m]);

  const loadHolding = useCallback(async () => {
    try {
      const p = await api.portfolio();
      const h = p.holdings.find((x) => x.symbol === symbol && x.market === m);
      setHolding(h || null);
      const w = await api.watchlist();
      setIsWatched(w.some((x: any) => x.symbol === symbol && x.market === m));
    } catch {}
  }, [symbol, m]);

  useEffect(() => {
    loadQuote();
    loadChart(range);
    loadHolding();
  }, [loadQuote, loadChart, loadHolding, range]);

  const place = async () => {
    const qtyN = parseFloat(qty);
    if (!qtyN || qtyN <= 0) {
      Alert.alert("Invalid quantity", "Enter a valid quantity");
      return;
    }
    setPlacing(true);
    try {
      const res = await api.placeOrder(symbol as string, m, showOrder as "buy" | "sell", qtyN);
      Alert.alert(
        `${showOrder?.toUpperCase()} executed`,
        `${qtyN} ${symbol} @ ${formatINR(res.price)}\nTotal: ${formatINR(res.total)}\nNew balance: ${formatINR(res.new_balance)}`
      );
      setShowOrder(null);
      setQty("");
      await refreshUser();
      await loadHolding();
    } catch (e: any) {
      Alert.alert("Order failed", e.message || "Could not place order");
    } finally {
      setPlacing(false);
    }
  };

  const toggleWatch = async () => {
    try {
      if (isWatched) {
        await api.removeWatch(symbol as string, m);
        setIsWatched(false);
      } else {
        await api.addWatch(symbol as string, m);
        setIsWatched(true);
      }
    } catch {}
  };

  const isUp = (quote?.change_pct || 0) >= 0;

  return (
    <SafeAreaView style={styles.safe} edges={["top"]}>
      <View style={styles.header}>
        <TouchableOpacity testID="back-button" onPress={() => router.back()} style={styles.iconBtn}>
          <Ionicons name="chevron-back" size={22} color={colors.ink} />
        </TouchableOpacity>
        <View style={{ flex: 1, alignItems: "center" }}>
          <Text style={styles.symbol}>{symbol}</Text>
          <Text style={styles.sub} numberOfLines={1}>{name || quote?.name}</Text>
        </View>
        <TouchableOpacity testID="watchlist-toggle" onPress={toggleWatch} style={styles.iconBtn}>
          <Ionicons name={isWatched ? "star" : "star-outline"} size={20} color={isWatched ? colors.imperialGold : colors.ink3} />
        </TouchableOpacity>
      </View>

      <ScrollView contentContainerStyle={{ paddingBottom: 120 }} showsVerticalScrollIndicator={false}>
        <View style={styles.priceBlock}>
          {quote ? (
            <>
              <Text testID="quote-price" style={styles.price}>{formatINR(quote.price)}</Text>
              <View style={[styles.changeBadge, { backgroundColor: isUp ? colors.bullLight : colors.bearLight }]}>
                <Ionicons name={isUp ? "trending-up" : "trending-down"} size={14} color={isUp ? colors.bull : colors.bear} />
                <Text style={[styles.changeText, { color: isUp ? colors.bull : colors.bear }]}>
                  {formatINR(quote.change)} ({formatPct(quote.change_pct)})
                </Text>
              </View>
            </>
          ) : (
            <ActivityIndicator color={colors.imperialGold} />
          )}
        </View>

        <View style={styles.chartWrap}>
          {loadingChart ? (
            <View style={{ height: 200, alignItems: "center", justifyContent: "center" }}>
              <ActivityIndicator color={colors.imperialGold} />
            </View>
          ) : (
            <PriceChart points={points} />
          )}
          <View style={styles.rangeRow}>
            {RANGES.map((r) => (
              <TouchableOpacity
                key={r.key}
                testID={`range-${r.key}`}
                onPress={() => setRange(r.key)}
                style={[styles.rangeBtn, range === r.key && styles.rangeActive]}
              >
                <Text style={[styles.rangeText, range === r.key && styles.rangeTextActive]}>{r.label}</Text>
              </TouchableOpacity>
            ))}
          </View>
        </View>

        {holding && (
          <View style={styles.holdingBox}>
            <Text style={styles.holdingLabel}>Your Position</Text>
            <View style={styles.holdingGrid}>
              <View style={styles.gridItem}>
                <Text style={styles.gridLabel}>Quantity</Text>
                <Text style={styles.gridValue}>{holding.quantity.toFixed(m === "crypto" ? 4 : 0)}</Text>
              </View>
              <View style={styles.gridItem}>
                <Text style={styles.gridLabel}>Avg Price</Text>
                <Text style={styles.gridValue}>{formatINR(holding.avg_price)}</Text>
              </View>
              <View style={styles.gridItem}>
                <Text style={styles.gridLabel}>Current Value</Text>
                <Text style={styles.gridValue}>{formatINR(holding.current)}</Text>
              </View>
              <View style={styles.gridItem}>
                <Text style={styles.gridLabel}>P&L</Text>
                <Text style={[styles.gridValue, { color: holding.pnl >= 0 ? colors.bull : colors.bear }]}>
                  {formatINR(holding.pnl)} ({formatPct(holding.pnl_pct)})
                </Text>
              </View>
            </View>
          </View>
        )}

        {quote && (
          <View style={styles.statsCard}>
            <Text style={styles.statsTitle}>Key Stats</Text>
            <StatRow label="Previous Close" value={formatINR(quote.previous_close)} />
            <StatRow label="Day Change" value={`${formatINR(quote.change)} (${formatPct(quote.change_pct)})`} valueColor={isUp ? colors.bull : colors.bear} />
            <StatRow label="Market" value={quote.market === "crypto" ? "Crypto" : "NSE/BSE"} />
            <StatRow label="Currency" value={quote.currency} />
          </View>
        )}
      </ScrollView>

      {/* Fixed Buy/Sell */}
      <View style={styles.footer}>
        <TouchableOpacity testID="open-buy-modal" style={[styles.actionBtn, styles.buyBtn]} onPress={() => setShowOrder("buy")} activeOpacity={0.85}>
          <Text style={styles.actionBtnText}>BUY</Text>
        </TouchableOpacity>
        <TouchableOpacity
          testID="open-sell-modal"
          style={[styles.actionBtn, styles.sellBtn, !holding && { opacity: 0.5 }]}
          onPress={() => holding && setShowOrder("sell")}
          activeOpacity={0.85}
          disabled={!holding}
        >
          <Text style={styles.actionBtnText}>SELL</Text>
        </TouchableOpacity>
      </View>

      {/* Order Modal */}
      <Modal visible={!!showOrder} transparent animationType="slide" onRequestClose={() => setShowOrder(null)}>
        <KeyboardAvoidingView behavior={Platform.OS === "ios" ? "padding" : undefined} style={styles.modalBg}>
          <View style={styles.modalCard}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>
                {showOrder === "buy" ? "Buy" : "Sell"} {symbol}
              </Text>
              <TouchableOpacity testID="close-modal" onPress={() => setShowOrder(null)}>
                <Ionicons name="close" size={22} color={colors.ink3} />
              </TouchableOpacity>
            </View>

            <View style={styles.modalRow}>
              <Text style={styles.modalLabel}>Current Price</Text>
              <Text style={styles.modalValue}>{quote ? formatINR(quote.price) : "—"}</Text>
            </View>
            <View style={styles.modalRow}>
              <Text style={styles.modalLabel}>Wallet</Text>
              <Text style={styles.modalValue}>{formatINR(user?.wallet_balance || 0)}</Text>
            </View>
            {holding && showOrder === "sell" && (
              <View style={styles.modalRow}>
                <Text style={styles.modalLabel}>Holding</Text>
                <Text style={styles.modalValue}>{holding.quantity.toFixed(m === "crypto" ? 4 : 0)} units</Text>
              </View>
            )}

            <Text style={styles.modalFieldLabel}>Quantity</Text>
            <TextInput
              testID="order-quantity-input"
              value={qty}
              onChangeText={setQty}
              keyboardType="decimal-pad"
              placeholder={m === "crypto" ? "0.001" : "1"}
              placeholderTextColor={colors.ink5}
              style={styles.modalInput}
            />

            {quote && qty && (
              <View style={[styles.modalRow, { marginTop: spacing.md }]}>
                <Text style={styles.modalLabel}>Estimated Total</Text>
                <Text style={[styles.modalValue, { fontFamily: fonts.bodyBold }]}>
                  {formatINR(parseFloat(qty || "0") * quote.price)}
                </Text>
              </View>
            )}

            <TouchableOpacity
              testID="confirm-order-button"
              style={[styles.confirmBtn, { backgroundColor: showOrder === "buy" ? colors.bull : colors.bear }, placing && { opacity: 0.7 }]}
              onPress={place}
              disabled={placing}
            >
              {placing ? <ActivityIndicator color={colors.parchment} /> : <Text style={styles.confirmText}>Confirm {showOrder?.toUpperCase()}</Text>}
            </TouchableOpacity>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </SafeAreaView>
  );
}

function StatRow({ label, value, valueColor }: { label: string; value: string; valueColor?: string }) {
  return (
    <View style={styles.statRow}>
      <Text style={styles.statLabel}>{label}</Text>
      <Text style={[styles.statValue, valueColor ? { color: valueColor } : null]}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  header: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.sm,
    paddingBottom: spacing.sm,
  },
  iconBtn: {
    width: 40,
    height: 40,
    borderRadius: radius.pill,
    backgroundColor: colors.cream,
    alignItems: "center",
    justifyContent: "center",
    borderWidth: 1,
    borderColor: colors.birch,
  },
  symbol: { fontFamily: fonts.displayBlack, fontSize: 20, color: colors.ink },
  sub: { fontFamily: fonts.body, fontSize: 12, color: colors.ink4 },
  priceBlock: { paddingHorizontal: spacing.lg, alignItems: "center", marginTop: spacing.md, marginBottom: spacing.lg },
  price: { fontFamily: fonts.displayBlack, fontSize: 40, color: colors.ink, letterSpacing: -0.5 },
  changeBadge: { flexDirection: "row", alignItems: "center", gap: 4, paddingHorizontal: spacing.sm, paddingVertical: 4, borderRadius: radius.tag, marginTop: spacing.sm },
  changeText: { fontFamily: fonts.monoMed, fontSize: 13 },
  chartWrap: { paddingHorizontal: spacing.lg },
  rangeRow: { flexDirection: "row", justifyContent: "space-between", marginTop: spacing.md, backgroundColor: colors.cream, borderRadius: radius.md, padding: 4, borderWidth: 1, borderColor: colors.birch },
  rangeBtn: { flex: 1, paddingVertical: 8, alignItems: "center", borderRadius: radius.sm },
  rangeActive: { backgroundColor: colors.pureWhite, ...shadow.sm },
  rangeText: { fontFamily: fonts.bodyMed, fontSize: 12, color: colors.ink4 },
  rangeTextActive: { color: colors.ink, fontFamily: fonts.bodyBold },
  holdingBox: { margin: spacing.lg, backgroundColor: colors.pureWhite, borderRadius: radius.lg, padding: spacing.lg, borderWidth: 1, borderColor: colors.birch, ...shadow.sm },
  holdingLabel: { fontFamily: fonts.bodyMed, fontSize: 12, color: colors.ink4, textTransform: "uppercase", letterSpacing: 0.5 },
  holdingGrid: { flexDirection: "row", flexWrap: "wrap", marginTop: spacing.sm },
  gridItem: { width: "50%", paddingVertical: spacing.sm },
  gridLabel: { fontFamily: fonts.body, fontSize: 11, color: colors.ink4 },
  gridValue: { fontFamily: fonts.monoMed, fontSize: 14, color: colors.ink, marginTop: 2 },
  statsCard: { marginHorizontal: spacing.lg, backgroundColor: colors.pureWhite, borderRadius: radius.lg, padding: spacing.lg, borderWidth: 1, borderColor: colors.birch },
  statsTitle: { fontFamily: fonts.display, fontSize: 16, color: colors.ink, marginBottom: spacing.sm },
  statRow: { flexDirection: "row", justifyContent: "space-between", paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: colors.cream },
  statLabel: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4 },
  statValue: { fontFamily: fonts.monoMed, fontSize: 13, color: colors.ink },
  footer: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    flexDirection: "row",
    padding: spacing.md,
    backgroundColor: colors.warmWhite,
    borderTopWidth: 1,
    borderTopColor: colors.birch,
    gap: spacing.sm,
  },
  actionBtn: { flex: 1, paddingVertical: 14, borderRadius: radius.md, alignItems: "center", ...shadow.md },
  buyBtn: { backgroundColor: colors.bull },
  sellBtn: { backgroundColor: colors.bear },
  actionBtnText: { fontFamily: fonts.bodyBold, fontSize: 15, color: colors.parchment, letterSpacing: 1 },
  modalBg: { flex: 1, backgroundColor: "rgba(26,18,8,0.5)", justifyContent: "flex-end" },
  modalCard: { backgroundColor: colors.pureWhite, borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl, padding: spacing.xl, paddingBottom: spacing.xxl },
  modalHeader: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: spacing.md },
  modalTitle: { fontFamily: fonts.display, fontSize: 22, color: colors.ink },
  modalRow: { flexDirection: "row", justifyContent: "space-between", paddingVertical: 8 },
  modalLabel: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4 },
  modalValue: { fontFamily: fonts.monoMed, fontSize: 13, color: colors.ink },
  modalFieldLabel: { fontFamily: fonts.bodyMed, fontSize: 12, color: colors.ink3, marginTop: spacing.md, marginBottom: 6 },
  modalInput: { backgroundColor: colors.cream, borderWidth: 1, borderColor: colors.birch, borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: 12, fontFamily: fonts.mono, fontSize: 16, color: colors.ink },
  confirmBtn: { paddingVertical: 14, borderRadius: radius.md, alignItems: "center", marginTop: spacing.lg },
  confirmText: { fontFamily: fonts.bodyBold, fontSize: 15, color: colors.parchment, letterSpacing: 1 },
});
