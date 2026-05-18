import React, { useCallback, useState } from "react";
import { View, Text, StyleSheet, FlatList, RefreshControl } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useFocusEffect } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, shadow, formatINR } from "@/src/theme";
import { api } from "@/src/api/client";

export default function Compete() {
  const [data, setData] = useState<any[]>([]);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    try {
      const d = await api.leaderboard();
      setData(d);
    } catch (e) {
      console.warn(e);
    }
  }, []);

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

  const top3 = data.slice(0, 3);
  const rest = data.slice(3);

  return (
    <SafeAreaView style={styles.safe} edges={["top"]}>
      <FlatList
        data={rest}
        keyExtractor={(it) => it.user_id}
        contentContainerStyle={{ padding: spacing.lg, paddingBottom: spacing.xxl }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.imperialGold} />}
        ListHeaderComponent={
          <>
            <Text style={styles.title}>Weekly League</Text>
            <Text style={styles.subtitle}>Best realised P&L wins. New week resets every Monday.</Text>
            <View style={styles.podium}>
              {top3.map((u, i) => (
                <View
                  key={u.user_id}
                  testID={`podium-${i + 1}`}
                  style={[
                    styles.podiumCard,
                    i === 0 && styles.podiumGold,
                    i === 1 && styles.podiumSilver,
                    i === 2 && styles.podiumBronze,
                  ]}
                >
                  <View style={styles.medalCircle}>
                    <Text style={styles.medalText}>{i + 1}</Text>
                  </View>
                  <Text style={styles.podiumName} numberOfLines={1}>{u.name}</Text>
                  <Text style={[styles.podiumPnl, { color: u.realized_pnl >= 0 ? colors.bull : colors.bear }]}>
                    {formatINR(u.realized_pnl, 0)}
                  </Text>
                  {u.is_self && <View style={styles.youBadge}><Text style={styles.youBadgeText}>YOU</Text></View>}
                </View>
              ))}
              {top3.length === 0 && (
                <View style={styles.emptyPodium}>
                  <Ionicons name="trophy-outline" size={32} color={colors.goldDeep} />
                  <Text style={styles.emptyPodiumText}>Be the first Titan to top the board</Text>
                </View>
              )}
            </View>

            {rest.length > 0 && <Text style={styles.listTitle}>All Traders</Text>}
          </>
        }
        renderItem={({ item, index }) => (
          <View testID={`leader-row-${item.rank}`} style={[styles.row, item.is_self && styles.rowSelf]}>
            <Text style={styles.rank}>#{item.rank}</Text>
            <View style={{ flex: 1 }}>
              <Text style={styles.name}>{item.name}{item.is_self ? " (You)" : ""}</Text>
            </View>
            <Text style={[styles.pnl, { color: item.realized_pnl >= 0 ? colors.bull : colors.bear }]}>
              {formatINR(item.realized_pnl, 0)}
            </Text>
          </View>
        )}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  title: { fontFamily: fonts.displayBlack, fontSize: 28, color: colors.ink },
  subtitle: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4, marginTop: 2, marginBottom: spacing.lg },
  podium: { flexDirection: "row", justifyContent: "space-between", gap: spacing.sm, marginBottom: spacing.xl },
  podiumCard: {
    flex: 1,
    backgroundColor: colors.pureWhite,
    borderRadius: radius.lg,
    padding: spacing.md,
    alignItems: "center",
    borderWidth: 2,
    borderColor: colors.birch,
    ...shadow.md,
  },
  podiumGold: { borderColor: colors.imperialGold, backgroundColor: colors.goldPale },
  podiumSilver: { borderColor: "#A8A8A8", backgroundColor: "#F5F5F5" },
  podiumBronze: { borderColor: "#CD7F32", backgroundColor: "#FBE6D4" },
  medalCircle: { width: 36, height: 36, borderRadius: radius.pill, backgroundColor: colors.ink, alignItems: "center", justifyContent: "center" },
  medalText: { fontFamily: fonts.displayBlack, fontSize: 16, color: colors.goldLight },
  podiumName: { fontFamily: fonts.bodyBold, fontSize: 12, color: colors.ink, marginTop: spacing.sm, maxWidth: "100%" },
  podiumPnl: { fontFamily: fonts.monoMed, fontSize: 13, marginTop: 4 },
  youBadge: { position: "absolute", top: -8, right: -8, backgroundColor: colors.imperialGold, paddingHorizontal: 6, paddingVertical: 2, borderRadius: radius.tag },
  youBadgeText: { fontFamily: fonts.bodyBold, fontSize: 9, color: colors.parchment },
  emptyPodium: { flex: 1, alignItems: "center", padding: spacing.xl },
  emptyPodiumText: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4, marginTop: spacing.sm, textAlign: "center" },
  listTitle: { fontFamily: fonts.display, fontSize: 18, color: colors.ink, marginBottom: spacing.sm },
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
  rowSelf: { borderColor: colors.imperialGold, backgroundColor: colors.goldPale },
  rank: { fontFamily: fonts.monoMed, fontSize: 14, color: colors.ink3, width: 40 },
  name: { fontFamily: fonts.bodyMed, fontSize: 14, color: colors.ink },
  pnl: { fontFamily: fonts.monoMed, fontSize: 14 },
});
