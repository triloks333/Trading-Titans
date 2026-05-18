import React, { useCallback, useState } from "react";
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, ActivityIndicator } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useRouter, useFocusEffect } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, shadow, formatINR, formatPct } from "@/src/theme";
import { api } from "@/src/api/client";

export default function Autopsy() {
  const router = useRouter();
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const d = await api.autopsy();
      setData(d);
    } catch (e) {
      console.warn(e);
    } finally {
      setLoading(false);
    }
  }, []);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  return (
    <SafeAreaView style={styles.safe} edges={["top"]}>
      <View style={styles.header}>
        <TouchableOpacity testID="autopsy-back" onPress={() => router.back()} style={styles.iconBtn}>
          <Ionicons name="chevron-back" size={22} color={colors.ink} />
        </TouchableOpacity>
        <Text style={styles.title}>Loss Autopsy</Text>
        <View style={{ width: 40 }} />
      </View>

      <ScrollView contentContainerStyle={styles.scroll}>
        <View style={styles.heroCard}>
          <Ionicons name="medkit" size={28} color={colors.bear} />
          <Text style={styles.heroTitle}>Your Loss Lessons</Text>
          <Text style={styles.heroSub}>Every loss is a tuition fee. Read the postmortem below.</Text>
        </View>

        {loading ? (
          <ActivityIndicator color={colors.imperialGold} style={{ marginTop: spacing.xl }} />
        ) : data ? (
          <>
            <View style={styles.summaryCard}>
              <Text style={styles.summaryText}>{data.summary}</Text>
            </View>

            {data.insights.map((it: any, i: number) => (
              <View key={i} testID={`autopsy-${i}`} style={styles.insightCard}>
                <View style={styles.insightHead}>
                  <Text style={styles.insightSym}>{it.symbol}</Text>
                  <View style={[styles.typeBadge, { backgroundColor: it.type === "closed_loss" ? colors.bearLight : colors.goldPale }]}>
                    <Text style={[styles.typeText, { color: it.type === "closed_loss" ? colors.bear : colors.goldDeep }]}>
                      {it.type === "closed_loss" ? "REALIZED" : "OPEN"}
                    </Text>
                  </View>
                </View>
                <Text style={styles.insightName} numberOfLines={1}>{it.name}</Text>
                <Text style={[styles.lossAmount, { color: colors.bear }]}>
                  {formatINR(it.loss, 0)} ({formatPct(it.loss_pct)})
                </Text>
                <View style={styles.tipBox}>
                  <Ionicons name="bulb-outline" size={16} color={colors.goldDeep} />
                  <Text style={styles.tipText}>{it.tip}</Text>
                </View>
              </View>
            ))}
          </>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  header: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingHorizontal: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.sm },
  iconBtn: { width: 40, height: 40, borderRadius: radius.pill, backgroundColor: colors.cream, alignItems: "center", justifyContent: "center", borderWidth: 1, borderColor: colors.birch },
  title: { fontFamily: fonts.display, fontSize: 18, color: colors.ink },
  scroll: { padding: spacing.lg, paddingBottom: spacing.xxl },
  heroCard: { backgroundColor: colors.bearLight, padding: spacing.lg, borderRadius: radius.xl, borderWidth: 1, borderColor: colors.bear, alignItems: "center" },
  heroTitle: { fontFamily: fonts.displayBlack, fontSize: 22, color: colors.ink, marginTop: spacing.sm },
  heroSub: { fontFamily: fonts.body, fontSize: 13, color: colors.ink3, marginTop: 4, textAlign: "center" },
  summaryCard: { marginTop: spacing.md, padding: spacing.md, backgroundColor: colors.pureWhite, borderRadius: radius.lg, borderWidth: 1, borderColor: colors.birch },
  summaryText: { fontFamily: fonts.bodyMed, fontSize: 14, color: colors.ink },
  insightCard: { marginTop: spacing.md, padding: spacing.lg, backgroundColor: colors.pureWhite, borderRadius: radius.lg, borderWidth: 1, borderColor: colors.birch, ...shadow.sm },
  insightHead: { flexDirection: "row", justifyContent: "space-between", alignItems: "center" },
  insightSym: { fontFamily: fonts.bodyBold, fontSize: 16, color: colors.ink },
  typeBadge: { paddingHorizontal: 8, paddingVertical: 2, borderRadius: radius.tag },
  typeText: { fontFamily: fonts.bodyBold, fontSize: 10, letterSpacing: 0.5 },
  insightName: { fontFamily: fonts.body, fontSize: 12, color: colors.ink4, marginTop: 2 },
  lossAmount: { fontFamily: fonts.monoMed, fontSize: 16, marginTop: 6 },
  tipBox: { flexDirection: "row", gap: 8, backgroundColor: colors.goldPale, padding: spacing.sm, borderRadius: radius.md, marginTop: spacing.sm, borderWidth: 1, borderColor: colors.goldBorder, alignItems: "flex-start" },
  tipText: { flex: 1, fontFamily: fonts.body, fontSize: 13, color: colors.ink2, lineHeight: 18 },
});
