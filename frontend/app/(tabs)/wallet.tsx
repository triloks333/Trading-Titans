import React, { useCallback, useState } from "react";
import { View, Text, StyleSheet, TouchableOpacity, FlatList, RefreshControl } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useFocusEffect, useRouter } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, shadow, formatINR } from "@/src/theme";
import { api, Order } from "@/src/api/client";
import { useAuth } from "@/src/context/AuthContext";

export default function Wallet() {
  const { user, refreshUser } = useAuth();
  const router = useRouter();
  const [orders, setOrders] = useState<Order[]>([]);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    try {
      await refreshUser();
      const o = await api.orders();
      setOrders(o);
    } catch (e) {
      console.warn(e);
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

  return (
    <SafeAreaView style={styles.safe} edges={["top"]}>
      <FlatList
        data={orders}
        keyExtractor={(o, i) => `${o.symbol}-${o.created_at}-${i}`}
        contentContainerStyle={{ padding: spacing.lg, paddingBottom: spacing.xxl }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.imperialGold} />}
        ListHeaderComponent={
          <>
            <Text style={styles.title}>Wallet</Text>

            <View style={styles.balCard}>
              <Text style={styles.balLabel}>Demo Cash Balance</Text>
              <Text testID="wallet-balance" style={styles.balValue}>{formatINR(user?.wallet_balance || 0, 2)}</Text>
              <View style={styles.subStatus}>
                <View style={[styles.statusPill, { backgroundColor: colors.bullLight }]}>
                  <Ionicons name="checkmark-circle" size={14} color={colors.bull} />
                  <Text style={[styles.statusText, { color: colors.bull }]}>
                    {user?.subscription_active ? "Active · Trading enabled" : "Free Starter"}
                  </Text>
                </View>
              </View>
            </View>

            <TouchableOpacity
              testID="wallet-subscribe-button"
              style={styles.ctaBtn}
              onPress={() => router.push("/subscribe")}
              activeOpacity={0.85}
            >
              <View>
                <Text style={styles.ctaTitle}>Top-up Demo Cash</Text>
                <Text style={styles.ctaSub}>From ₹199 · Up to ₹10,00,000</Text>
              </View>
              <Ionicons name="arrow-forward-circle" size={28} color={colors.pureWhite} />
            </TouchableOpacity>

            <Text style={styles.section}>Transaction History</Text>
          </>
        }
        renderItem={({ item }) => (
          <View style={styles.row}>
            <View style={[styles.sideTag, { backgroundColor: item.side === "buy" ? colors.bullLight : item.side === "sell" ? colors.bearLight : colors.goldPale }]}>
              <Text style={[styles.sideText, { color: item.side === "buy" ? colors.bull : item.side === "sell" ? colors.bear : colors.goldDeep }]}>
                {item.side.toUpperCase()}
              </Text>
            </View>
            <View style={{ flex: 1 }}>
              <Text style={styles.rowSym}>{item.symbol}</Text>
              <Text style={styles.rowMeta}>
                {item.quantity.toFixed(item.market === "crypto" ? 4 : 0)} @ {formatINR(item.price)}
              </Text>
            </View>
            <View style={{ alignItems: "flex-end" }}>
              <Text style={styles.rowTotal}>{formatINR(item.total, 0)}</Text>
              <Text style={styles.rowDate}>{new Date(item.created_at).toLocaleDateString("en-IN")}</Text>
            </View>
          </View>
        )}
        ListEmptyComponent={<Text style={styles.empty}>No transactions yet. Place your first order.</Text>}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  title: { fontFamily: fonts.displayBlack, fontSize: 28, color: colors.ink, marginBottom: spacing.md },
  balCard: {
    backgroundColor: colors.pureWhite,
    borderRadius: radius.xl,
    padding: spacing.xl,
    alignItems: "center",
    borderWidth: 1,
    borderColor: colors.goldBorder,
    ...shadow.md,
  },
  balLabel: { fontFamily: fonts.bodyMed, fontSize: 12, color: colors.ink4, letterSpacing: 0.5, textTransform: "uppercase" },
  balValue: { fontFamily: fonts.displayBlack, fontSize: 40, color: colors.ink, marginTop: spacing.sm, letterSpacing: -0.5 },
  subStatus: { marginTop: spacing.md },
  statusPill: { flexDirection: "row", alignItems: "center", paddingHorizontal: spacing.sm, paddingVertical: 4, borderRadius: radius.tag, gap: 4 },
  statusText: { fontFamily: fonts.bodyMed, fontSize: 12 },
  ctaBtn: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    backgroundColor: colors.ink,
    padding: spacing.lg,
    borderRadius: radius.lg,
    marginTop: spacing.md,
    borderWidth: 1,
    borderColor: colors.goldBorder,
    ...shadow.gold,
  },
  ctaTitle: { fontFamily: fonts.display, fontSize: 18, color: colors.pureWhite },
  ctaSub: { fontFamily: fonts.body, fontSize: 13, color: colors.goldLight, marginTop: 2 },
  titanCard: {
    flexDirection: "row",
    alignItems: "center",
    gap: spacing.sm,
    backgroundColor: colors.goldPale,
    padding: spacing.md,
    borderRadius: radius.lg,
    marginTop: spacing.md,
    borderWidth: 1,
    borderColor: colors.goldBorder,
  },
  titanText: { fontFamily: fonts.bodyMed, fontSize: 14, color: colors.goldDeep },
  section: { fontFamily: fonts.display, fontSize: 18, color: colors.ink, marginTop: spacing.xl, marginBottom: spacing.sm },
  row: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: colors.warmWhite,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.birch,
    marginBottom: spacing.sm,
    gap: spacing.md,
  },
  sideTag: { paddingHorizontal: 8, paddingVertical: 4, borderRadius: radius.tag },
  sideText: { fontFamily: fonts.bodyBold, fontSize: 10, letterSpacing: 0.5 },
  rowSym: { fontFamily: fonts.bodyBold, fontSize: 14, color: colors.ink },
  rowMeta: { fontFamily: fonts.body, fontSize: 12, color: colors.ink4, marginTop: 2 },
  rowTotal: { fontFamily: fonts.monoMed, fontSize: 14, color: colors.ink },
  rowDate: { fontFamily: fonts.body, fontSize: 11, color: colors.ink4, marginTop: 2 },
  empty: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4, textAlign: "center", marginTop: spacing.xl },
});
