import React, { useCallback, useState } from "react";
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, ActivityIndicator } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useRouter, useFocusEffect } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, shadow, formatINR } from "@/src/theme";
import { api } from "@/src/api/client";

export default function Analytics() {
  const router = useRouter();
  const [data, setData] = useState<any>(null);

  const load = useCallback(async () => {
    try {
      const d = await api.analytics();
      setData(d);
    } catch (e) { console.warn(e); }
  }, []);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  return (
    <SafeAreaView style={styles.safe} edges={["top"]}>
      <View style={styles.header}>
        <TouchableOpacity testID="analytics-back" onPress={() => router.back()} style={styles.iconBtn}>
          <Ionicons name="chevron-back" size={22} color={colors.ink} />
        </TouchableOpacity>
        <Text style={styles.title}>Analytics</Text>
        <View style={{ width: 40 }} />
      </View>

      <ScrollView contentContainerStyle={styles.scroll}>
        {!data ? (
          <ActivityIndicator color={colors.imperialGold} style={{ marginTop: spacing.xl }} />
        ) : (
          <>
            <View style={styles.heroCard}>
              <Text style={styles.heroLabel}>Total Realized P&L</Text>
              <Text style={[styles.heroValue, { color: data.realized_pnl >= 0 ? colors.bull : colors.bear }]}>
                {formatINR(data.realized_pnl)}
              </Text>
            </View>

            <View style={styles.statsGrid}>
              <Stat label="Total Trades" value={String(data.total_trades)} />
              <Stat label="Win Rate" value={`${data.win_rate}%`} />
              <Stat label="Buys" value={String(data.buy_trades)} />
              <Stat label="Sells" value={String(data.sell_trades)} />
              <Stat label="Winning Trades" value={String(data.winning_trades)} color={colors.bull} />
              <Stat label="Losing Trades" value={String(data.losing_trades)} color={colors.bear} />
            </View>

            {data.best_trade && (
              <View style={[styles.tradeCard, { borderColor: colors.bull }]}>
                <View style={styles.tradeHeader}>
                  <Ionicons name="trophy" size={20} color={colors.bull} />
                  <Text style={styles.tradeTitle}>Best Trade</Text>
                </View>
                <Text style={styles.tradeSym}>{data.best_trade.symbol} · {data.best_trade.name}</Text>
                <Text style={[styles.tradePnl, { color: colors.bull }]}>{formatINR(data.best_trade.realized_pnl)}</Text>
              </View>
            )}
            {data.worst_trade && (
              <View style={[styles.tradeCard, { borderColor: colors.bear }]}>
                <View style={styles.tradeHeader}>
                  <Ionicons name="warning" size={20} color={colors.bear} />
                  <Text style={styles.tradeTitle}>Worst Trade</Text>
                </View>
                <Text style={styles.tradeSym}>{data.worst_trade.symbol} · {data.worst_trade.name}</Text>
                <Text style={[styles.tradePnl, { color: colors.bear }]}>{formatINR(data.worst_trade.realized_pnl)}</Text>
              </View>
            )}
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function Stat({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <View style={styles.statCard}>
      <Text style={styles.statLabel}>{label}</Text>
      <Text style={[styles.statValue, color ? { color } : null]}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  header: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingHorizontal: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.sm },
  iconBtn: { width: 40, height: 40, borderRadius: radius.pill, backgroundColor: colors.cream, alignItems: "center", justifyContent: "center", borderWidth: 1, borderColor: colors.birch },
  title: { fontFamily: fonts.display, fontSize: 18, color: colors.ink },
  scroll: { padding: spacing.lg },
  heroCard: { backgroundColor: colors.pureWhite, padding: spacing.xl, borderRadius: radius.xl, borderWidth: 1, borderColor: colors.goldBorder, alignItems: "center", ...shadow.md },
  heroLabel: { fontFamily: fonts.bodyMed, fontSize: 12, color: colors.ink4, textTransform: "uppercase", letterSpacing: 0.5 },
  heroValue: { fontFamily: fonts.displayBlack, fontSize: 36, marginTop: spacing.sm, letterSpacing: -0.5 },
  statsGrid: { flexDirection: "row", flexWrap: "wrap", marginTop: spacing.md, gap: spacing.sm },
  statCard: { width: "48%", backgroundColor: colors.warmWhite, padding: spacing.md, borderRadius: radius.lg, borderWidth: 1, borderColor: colors.birch },
  statLabel: { fontFamily: fonts.body, fontSize: 12, color: colors.ink4 },
  statValue: { fontFamily: fonts.monoMed, fontSize: 18, color: colors.ink, marginTop: 4 },
  tradeCard: { marginTop: spacing.md, padding: spacing.lg, backgroundColor: colors.pureWhite, borderRadius: radius.lg, borderWidth: 2 },
  tradeHeader: { flexDirection: "row", alignItems: "center", gap: 6 },
  tradeTitle: { fontFamily: fonts.bodyBold, fontSize: 14, color: colors.ink3, textTransform: "uppercase", letterSpacing: 0.5 },
  tradeSym: { fontFamily: fonts.body, fontSize: 14, color: colors.ink, marginTop: 4 },
  tradePnl: { fontFamily: fonts.displayBlack, fontSize: 24, marginTop: 4 },
});
