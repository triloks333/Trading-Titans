import React, { useCallback, useEffect, useState } from "react";
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  RefreshControl,
  FlatList,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useRouter, useFocusEffect } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, shadow, formatINR, formatPct } from "@/src/theme";
import CrownLogo from "@/src/components/CrownLogo";
import { api, Portfolio, Quote } from "@/src/api/client";
import { useAuth } from "@/src/context/AuthContext";

export default function Dashboard() {
  const { user, refreshUser } = useAuth();
  const router = useRouter();
  const [portfolio, setPortfolio] = useState<Portfolio | null>(null);
  const [overview, setOverview] = useState<Quote[]>([]);
  const [watchlist, setWatchlist] = useState<any[]>([]);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    try {
      const [p, o, w] = await Promise.all([
        api.portfolio().catch(() => null),
        api.marketOverview().catch(() => []),
        api.watchlist().catch(() => []),
      ]);
      setPortfolio(p);
      setOverview(o);
      setWatchlist(w);
      await refreshUser();
    } catch (e) {
      console.warn("load dashboard", e);
    }
  }, [refreshUser]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  const onRefresh = async () => {
    setRefreshing(true);
    await load();
    setRefreshing(false);
  };

  const totalValue = (portfolio?.wallet_balance || 0) + (portfolio?.current_value || 0);
  const totalPnL = (portfolio?.unrealized_pnl || 0) + (portfolio?.realized_pnl || 0);
  const isPositive = totalPnL >= 0;

  return (
    <SafeAreaView style={styles.safe} edges={["top"]}>
      <ScrollView
        contentContainerStyle={styles.scroll}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.imperialGold} />}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <View style={styles.header}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: spacing.sm }}>
            <CrownLogo size={36} withRing={false} />
            <View>
              <Text style={styles.greet}>Welcome,</Text>
              <Text style={styles.userName}>{user?.name || "Titan"}</Text>
            </View>
          </View>
          <TouchableOpacity
            testID="header-orders-button"
            style={styles.iconBtn}
            onPress={() => router.push("/orders")}
          >
            <Ionicons name="receipt-outline" size={20} color={colors.ink2} />
          </TouchableOpacity>
        </View>

        {/* Portfolio card */}
        <View style={styles.portfolioCard}>
          <Text style={styles.cardLabel}>Total Portfolio Value</Text>
          <Text testID="total-portfolio-value" style={styles.bigValue}>
            {formatINR(totalValue)}
          </Text>
          <View style={styles.pnlRow}>
            <View
              style={[
                styles.pnlBadge,
                { backgroundColor: isPositive ? colors.bullLight : colors.bearLight },
              ]}
            >
              <Ionicons
                name={isPositive ? "trending-up" : "trending-down"}
                size={14}
                color={isPositive ? colors.bull : colors.bear}
              />
              <Text style={[styles.pnlText, { color: isPositive ? colors.bull : colors.bear }]}>
                {formatINR(totalPnL)} ({formatPct((totalPnL / Math.max(1, totalValue - totalPnL)) * 100)})
              </Text>
            </View>
          </View>
          <View style={styles.statsRow}>
            <View style={styles.statBox}>
              <Text style={styles.statLabel}>Wallet</Text>
              <Text style={styles.statValue}>{formatINR(portfolio?.wallet_balance || 0, 0)}</Text>
            </View>
            <View style={styles.statBox}>
              <Text style={styles.statLabel}>Invested</Text>
              <Text style={styles.statValue}>{formatINR(portfolio?.invested_value || 0, 0)}</Text>
            </View>
            <View style={styles.statBox}>
              <Text style={styles.statLabel}>Holdings</Text>
              <Text style={styles.statValue}>{portfolio?.holdings?.length || 0}</Text>
            </View>
          </View>
        </View>

        {/* Subscription banner */}
        {!user?.subscription_active && (
          <TouchableOpacity
            testID="subscribe-banner"
            style={styles.subBanner}
            onPress={() => router.push("/subscribe")}
            activeOpacity={0.85}
          >
            <View style={{ flex: 1 }}>
              <Text style={styles.subBannerTitle}>Activate Titan Plan</Text>
              <Text style={styles.subBannerSub}>Pay ₹199 · Unlock ₹1,00,000 demo cash</Text>
            </View>
            <Ionicons name="arrow-forward" size={20} color={colors.parchment} />
          </TouchableOpacity>
        )}

        {/* Quick actions */}
        <View style={styles.actionsRow}>
          <ActionTile
            testID="quick-trade"
            icon="search"
            label="Trade"
            onPress={() => router.push("/(tabs)/trade")}
          />
          <ActionTile
            testID="quick-whatif"
            icon="bulb-outline"
            label="What-If"
            onPress={() => router.push("/whatif")}
          />
          <ActionTile
            testID="quick-autopsy"
            icon="medkit-outline"
            label="Autopsy"
            onPress={() => router.push("/autopsy")}
          />
          <ActionTile
            testID="quick-analytics"
            icon="stats-chart-outline"
            label="Analytics"
            onPress={() => router.push("/analytics")}
          />
        </View>

        {/* Market overview */}
        <Text style={styles.sectionTitle}>Market Pulse</Text>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginHorizontal: -spacing.lg }} contentContainerStyle={{ paddingHorizontal: spacing.lg, gap: spacing.sm }}>
          {overview.map((q) => (
            <TouchableOpacity
              key={q.symbol}
              testID={`market-ticker-${q.symbol}`}
              style={styles.tickerCard}
              onPress={() =>
                router.push({
                  pathname: "/stock/[symbol]",
                  params: { symbol: q.symbol, market: q.market, name: q.display_name || q.name },
                })
              }
            >
              <Text style={styles.tickerName} numberOfLines={1}>
                {q.display_name || q.name}
              </Text>
              <Text style={styles.tickerPrice}>{q.price.toLocaleString("en-IN")}</Text>
              <Text style={[styles.tickerChange, { color: q.change_pct >= 0 ? colors.bull : colors.bear }]}>
                {formatPct(q.change_pct)}
              </Text>
            </TouchableOpacity>
          ))}
        </ScrollView>

        {/* Holdings preview */}
        {portfolio?.holdings && portfolio.holdings.length > 0 && (
          <>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>Your Holdings</Text>
            </View>
            {portfolio.holdings.slice(0, 5).map((h) => (
              <TouchableOpacity
                key={`${h.symbol}-${h.market}`}
                testID={`holding-${h.symbol}`}
                style={styles.holdingRow}
                onPress={() =>
                  router.push({ pathname: "/stock/[symbol]", params: { symbol: h.symbol, market: h.market, name: h.name } })
                }
              >
                <View style={{ flex: 1 }}>
                  <Text style={styles.holdingSym}>{h.symbol}</Text>
                  <Text style={styles.holdingName} numberOfLines={1}>
                    {h.quantity.toFixed(h.market === "crypto" ? 4 : 0)} units · avg {formatINR(h.avg_price)}
                  </Text>
                </View>
                <View style={{ alignItems: "flex-end" }}>
                  <Text style={styles.holdingValue}>{formatINR(h.current)}</Text>
                  <Text style={[styles.holdingPnl, { color: h.pnl >= 0 ? colors.bull : colors.bear }]}>
                    {formatPct(h.pnl_pct)}
                  </Text>
                </View>
              </TouchableOpacity>
            ))}
          </>
        )}

        {/* Watchlist */}
        {watchlist.length > 0 && (
          <>
            <Text style={styles.sectionTitle}>Watchlist</Text>
            {watchlist.map((w: any) => (
              <TouchableOpacity
                key={`${w.symbol}-${w.market}`}
                testID={`watch-${w.symbol}`}
                style={styles.holdingRow}
                onPress={() =>
                  router.push({ pathname: "/stock/[symbol]", params: { symbol: w.symbol, market: w.market, name: w.name } })
                }
              >
                <View style={{ flex: 1 }}>
                  <Text style={styles.holdingSym}>{w.symbol}</Text>
                  <Text style={styles.holdingName} numberOfLines={1}>{w.name}</Text>
                </View>
                <View style={{ alignItems: "flex-end" }}>
                  <Text style={styles.holdingValue}>{w.price ? formatINR(w.price) : "—"}</Text>
                  <Text style={[styles.holdingPnl, { color: (w.change_pct || 0) >= 0 ? colors.bull : colors.bear }]}>
                    {w.change_pct !== undefined ? formatPct(w.change_pct) : ""}
                  </Text>
                </View>
              </TouchableOpacity>
            ))}
          </>
        )}

        <View style={{ height: 40 }} />
      </ScrollView>
    </SafeAreaView>
  );
}

function ActionTile({ icon, label, onPress, testID }: { icon: any; label: string; onPress: () => void; testID?: string }) {
  return (
    <TouchableOpacity testID={testID} style={styles.actionTile} onPress={onPress} activeOpacity={0.8}>
      <View style={styles.actionIcon}>
        <Ionicons name={icon} size={20} color={colors.goldDeep} />
      </View>
      <Text style={styles.actionLabel}>{label}</Text>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  scroll: { padding: spacing.lg, paddingBottom: spacing.xxl },
  header: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginBottom: spacing.lg },
  greet: { fontFamily: fonts.body, fontSize: 12, color: colors.ink4 },
  userName: { fontFamily: fonts.display, fontSize: 18, color: colors.ink },
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
  portfolioCard: {
    backgroundColor: colors.pureWhite,
    borderRadius: radius.xl,
    padding: spacing.lg,
    borderWidth: 1,
    borderColor: colors.birch,
    ...shadow.md,
  },
  cardLabel: { fontFamily: fonts.bodyMed, fontSize: 12, color: colors.ink4, letterSpacing: 0.5, textTransform: "uppercase" },
  bigValue: { fontFamily: fonts.displayBlack, fontSize: 36, color: colors.ink, marginTop: 4, letterSpacing: -0.5 },
  pnlRow: { flexDirection: "row", marginTop: spacing.sm },
  pnlBadge: { flexDirection: "row", alignItems: "center", paddingHorizontal: spacing.sm, paddingVertical: 4, borderRadius: radius.tag, gap: 4 },
  pnlText: { fontFamily: fonts.monoMed, fontSize: 13 },
  statsRow: { flexDirection: "row", marginTop: spacing.lg, gap: spacing.sm },
  statBox: { flex: 1, backgroundColor: colors.cream, padding: spacing.sm, borderRadius: radius.md, borderWidth: 1, borderColor: colors.birch },
  statLabel: { fontFamily: fonts.body, fontSize: 11, color: colors.ink4 },
  statValue: { fontFamily: fonts.monoMed, fontSize: 14, color: colors.ink, marginTop: 2 },
  subBanner: {
    marginTop: spacing.md,
    backgroundColor: colors.ink,
    borderRadius: radius.lg,
    padding: spacing.lg,
    flexDirection: "row",
    alignItems: "center",
    borderWidth: 1,
    borderColor: colors.goldBorder,
    ...shadow.gold,
  },
  subBannerTitle: { fontFamily: fonts.display, fontSize: 17, color: colors.goldLight },
  subBannerSub: { fontFamily: fonts.body, fontSize: 12, color: colors.parchment, marginTop: 2 },
  actionsRow: { flexDirection: "row", justifyContent: "space-between", marginTop: spacing.lg, gap: spacing.sm },
  actionTile: {
    flex: 1,
    backgroundColor: colors.warmWhite,
    paddingVertical: spacing.md,
    borderRadius: radius.lg,
    alignItems: "center",
    borderWidth: 1,
    borderColor: colors.birch,
  },
  actionIcon: {
    width: 36,
    height: 36,
    borderRadius: radius.pill,
    backgroundColor: colors.goldPale,
    alignItems: "center",
    justifyContent: "center",
    marginBottom: 4,
  },
  actionLabel: { fontFamily: fonts.bodyMed, fontSize: 12, color: colors.ink2 },
  sectionTitle: { fontFamily: fonts.display, fontSize: 20, color: colors.ink, marginTop: spacing.xl, marginBottom: spacing.sm },
  sectionHeader: { flexDirection: "row", justifyContent: "space-between", alignItems: "center" },
  tickerCard: {
    backgroundColor: colors.pureWhite,
    borderRadius: radius.md,
    padding: spacing.md,
    minWidth: 130,
    borderWidth: 1,
    borderColor: colors.birch,
  },
  tickerName: { fontFamily: fonts.bodyMed, fontSize: 12, color: colors.ink3 },
  tickerPrice: { fontFamily: fonts.monoMed, fontSize: 15, color: colors.ink, marginTop: 4 },
  tickerChange: { fontFamily: fonts.monoMed, fontSize: 12, marginTop: 2 },
  holdingRow: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: colors.warmWhite,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.birch,
    marginBottom: spacing.sm,
  },
  holdingSym: { fontFamily: fonts.bodyBold, fontSize: 14, color: colors.ink },
  holdingName: { fontFamily: fonts.body, fontSize: 12, color: colors.ink4, marginTop: 2 },
  holdingValue: { fontFamily: fonts.monoMed, fontSize: 14, color: colors.ink },
  holdingPnl: { fontFamily: fonts.monoMed, fontSize: 12, marginTop: 2 },
});
