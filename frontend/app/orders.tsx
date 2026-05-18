import React, { useCallback, useState } from "react";
import { View, Text, StyleSheet, FlatList, TouchableOpacity } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useRouter, useFocusEffect } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, formatINR } from "@/src/theme";
import { api, Order } from "@/src/api/client";

export default function Orders() {
  const router = useRouter();
  const [orders, setOrders] = useState<Order[]>([]);

  const load = useCallback(async () => {
    try {
      const o = await api.orders();
      setOrders(o);
    } catch (e) { console.warn(e); }
  }, []);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  return (
    <SafeAreaView style={styles.safe} edges={["top"]}>
      <View style={styles.header}>
        <TouchableOpacity testID="orders-back" onPress={() => router.back()} style={styles.iconBtn}>
          <Ionicons name="chevron-back" size={22} color={colors.ink} />
        </TouchableOpacity>
        <Text style={styles.title}>Order History</Text>
        <View style={{ width: 40 }} />
      </View>
      <FlatList
        data={orders}
        keyExtractor={(o, i) => `${o.symbol}-${o.created_at}-${i}`}
        contentContainerStyle={{ padding: spacing.lg, paddingBottom: spacing.xxl }}
        renderItem={({ item }) => (
          <View style={styles.row}>
            <View style={[styles.sideTag, { backgroundColor: item.side === "buy" ? colors.bullLight : item.side === "sell" ? colors.bearLight : colors.goldPale }]}>
              <Text style={[styles.sideText, { color: item.side === "buy" ? colors.bull : item.side === "sell" ? colors.bear : colors.goldDeep }]}>
                {item.side.toUpperCase()}
              </Text>
            </View>
            <View style={{ flex: 1 }}>
              <Text style={styles.rowSym}>{item.symbol}</Text>
              <Text style={styles.rowMeta}>{item.quantity.toFixed(item.market === "crypto" ? 4 : 0)} @ {formatINR(item.price)}</Text>
              <Text style={styles.rowDate}>{new Date(item.created_at).toLocaleString("en-IN")}</Text>
            </View>
            <View style={{ alignItems: "flex-end" }}>
              <Text style={styles.rowTotal}>{formatINR(item.total)}</Text>
              {item.realized_pnl !== 0 && (
                <Text style={[styles.pnlText, { color: item.realized_pnl > 0 ? colors.bull : colors.bear }]}>
                  {formatINR(item.realized_pnl)}
                </Text>
              )}
            </View>
          </View>
        )}
        ListEmptyComponent={<Text style={styles.empty}>No orders yet</Text>}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  header: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingHorizontal: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.sm },
  iconBtn: { width: 40, height: 40, borderRadius: radius.pill, backgroundColor: colors.cream, alignItems: "center", justifyContent: "center", borderWidth: 1, borderColor: colors.birch },
  title: { fontFamily: fonts.display, fontSize: 18, color: colors.ink },
  row: { flexDirection: "row", alignItems: "center", backgroundColor: colors.warmWhite, paddingHorizontal: spacing.md, paddingVertical: spacing.md, borderRadius: radius.md, borderWidth: 1, borderColor: colors.birch, marginBottom: spacing.sm, gap: spacing.md },
  sideTag: { paddingHorizontal: 8, paddingVertical: 4, borderRadius: radius.tag },
  sideText: { fontFamily: fonts.bodyBold, fontSize: 10, letterSpacing: 0.5 },
  rowSym: { fontFamily: fonts.bodyBold, fontSize: 14, color: colors.ink },
  rowMeta: { fontFamily: fonts.body, fontSize: 12, color: colors.ink4, marginTop: 2 },
  rowDate: { fontFamily: fonts.body, fontSize: 11, color: colors.ink5, marginTop: 2 },
  rowTotal: { fontFamily: fonts.monoMed, fontSize: 14, color: colors.ink },
  pnlText: { fontFamily: fonts.monoMed, fontSize: 12, marginTop: 2 },
  empty: { fontFamily: fonts.body, color: colors.ink4, textAlign: "center", marginTop: spacing.xl },
});
