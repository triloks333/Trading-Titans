import React, { useCallback, useEffect, useState } from "react";
import { View, Text, StyleSheet, TouchableOpacity, ScrollView, Alert, ActivityIndicator } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useRouter, useFocusEffect } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, shadow, formatINR } from "@/src/theme";
import { api } from "@/src/api/client";
import { useAuth } from "@/src/context/AuthContext";

interface Plan {
  id: string;
  name: string;
  price: number;
  cash: number;
}

const FEATURES = [
  "Real-time NSE/BSE + Crypto",
  "Unlimited paper trades",
  "Live leaderboard ranking",
  "Loss Autopsy + What-If",
];

export default function Subscribe() {
  const router = useRouter();
  const { refreshUser, user } = useAuth();
  const [plans, setPlans] = useState<Plan[]>([]);
  const [selected, setSelected] = useState<string>("titan_1l");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const p = await api.listPlans();
      setPlans(p);
    } catch {}
  }, []);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  const onPay = async () => {
    setBusy(true);
    try {
      const order = await api.createSubscriptionOrder(selected);
      Alert.alert(
        "Confirm top-up",
        order.is_mock
          ? `MVP mode — payment is currently free.\nConfirm to credit ₹${order.plan.cash.toLocaleString("en-IN")} demo cash to your wallet.`
          : `Open Razorpay to pay ₹${order.plan.price}.`,
        [
          { text: "Cancel", style: "cancel", onPress: () => setBusy(false) },
          {
            text: order.is_mock ? "Credit cash" : `Pay ₹${order.plan.price}`,
            onPress: async () => {
              try {
                const r = await api.activateSubscription({ plan_id: selected, order_id: order.id });
                await refreshUser();
                Alert.alert("Done!", r.message, [
                  { text: "Start Trading", onPress: () => router.replace("/(tabs)/dashboard") },
                ]);
              } catch (e: any) {
                Alert.alert("Failed", e.message || "Try again");
              } finally {
                setBusy(false);
              }
            },
          },
        ]
      );
    } catch (e: any) {
      Alert.alert("Failed", e.message || "Try again");
      setBusy(false);
    }
  };

  return (
    <SafeAreaView style={styles.safe} edges={["top"]}>
      <View style={styles.header}>
        <TouchableOpacity testID="subscribe-back" onPress={() => router.back()} style={styles.iconBtn}>
          <Ionicons name="close" size={22} color={colors.ink} />
        </TouchableOpacity>
        <View style={{ width: 40 }} />
      </View>

      <ScrollView contentContainerStyle={styles.scroll}>
        <Text style={styles.title}>Top up your wallet</Text>
        <Text style={styles.subtitle}>Pick a plan. Free during MVP — payment is mocked.</Text>

        <View style={styles.balRow}>
          <Text style={styles.balLabel}>Current balance</Text>
          <Text style={styles.balValue}>{formatINR(user?.wallet_balance || 0, 0)}</Text>
        </View>

        {plans.map((p) => {
          const active = selected === p.id;
          const popular = p.id === "titan_5l";
          return (
            <TouchableOpacity
              key={p.id}
              testID={`plan-${p.id}`}
              style={[styles.planCard, active && styles.planCardActive]}
              onPress={() => setSelected(p.id)}
              activeOpacity={0.85}
            >
              {popular && (
                <View style={styles.popularBadge}>
                  <Text style={styles.popularText}>MOST POPULAR</Text>
                </View>
              )}
              <View style={styles.planHead}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.planName}>{p.name}</Text>
                  <Text style={styles.planCash}>₹{p.cash.toLocaleString("en-IN")} demo cash</Text>
                </View>
                <View style={[styles.radio, active && styles.radioActive]}>
                  {active && <View style={styles.radioDot} />}
                </View>
              </View>
              <View style={styles.priceRow2}>
                <Text style={styles.priceText}>₹{p.price}</Text>
                <Text style={styles.pricePer}> one-time</Text>
              </View>
            </TouchableOpacity>
          );
        })}

        <View style={styles.featuresCard}>
          {FEATURES.map((f, i) => (
            <View key={i} style={styles.featureRow}>
              <Ionicons name="checkmark-circle" size={18} color={colors.bull} />
              <Text style={styles.featureText}>{f}</Text>
            </View>
          ))}
        </View>

        <TouchableOpacity testID="pay-button" style={[styles.payBtn, busy && { opacity: 0.7 }]} onPress={onPay} disabled={busy || plans.length === 0}>
          {busy ? <ActivityIndicator color={colors.parchment} /> : <Text style={styles.payText}>Continue</Text>}
        </TouchableOpacity>

        <Text style={styles.disclaimer}>
          During MVP, payment is bypassed. Once Razorpay is wired with live keys, real ₹199/₹899/₹1499 charges will apply. Demo cash has no real-world value.
        </Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  header: { flexDirection: "row", justifyContent: "space-between", paddingHorizontal: spacing.lg, paddingTop: spacing.sm },
  iconBtn: { width: 40, height: 40, borderRadius: radius.pill, backgroundColor: colors.cream, alignItems: "center", justifyContent: "center", borderWidth: 1, borderColor: colors.birch },
  scroll: { padding: spacing.lg, paddingBottom: spacing.xxl },
  title: { fontFamily: fonts.displayBlack, fontSize: 26, color: colors.ink, marginTop: spacing.sm },
  subtitle: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4, marginTop: 4, marginBottom: spacing.lg },
  balRow: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", backgroundColor: colors.cream, padding: spacing.md, borderRadius: radius.md, borderWidth: 1, borderColor: colors.birch, marginBottom: spacing.lg },
  balLabel: { fontFamily: fonts.bodyMed, fontSize: 13, color: colors.ink3 },
  balValue: { fontFamily: fonts.bodyBold, fontSize: 18, color: colors.ink },
  planCard: { backgroundColor: colors.pureWhite, borderRadius: radius.xl, padding: spacing.lg, borderWidth: 2, borderColor: colors.birch, marginBottom: spacing.md, position: "relative" },
  planCardActive: { borderColor: colors.imperialGold, backgroundColor: colors.goldPale, ...shadow.gold },
  popularBadge: { position: "absolute", top: -10, right: spacing.lg, backgroundColor: colors.imperialGold, paddingHorizontal: spacing.sm, paddingVertical: 3, borderRadius: radius.tag },
  popularText: { fontFamily: fonts.bodyBold, fontSize: 9, color: colors.pureWhite, letterSpacing: 1 },
  planHead: { flexDirection: "row", alignItems: "center" },
  planName: { fontFamily: fonts.bodyBold, fontSize: 17, color: colors.ink },
  planCash: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4, marginTop: 2 },
  radio: { width: 22, height: 22, borderRadius: radius.pill, borderWidth: 2, borderColor: colors.ink4, alignItems: "center", justifyContent: "center" },
  radioActive: { borderColor: colors.imperialGold },
  radioDot: { width: 10, height: 10, borderRadius: radius.pill, backgroundColor: colors.imperialGold },
  priceRow2: { flexDirection: "row", alignItems: "baseline", marginTop: spacing.sm },
  priceText: { fontFamily: fonts.displayBlack, fontSize: 28, color: colors.ink, letterSpacing: -0.5 },
  pricePer: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4 },
  featuresCard: { backgroundColor: colors.pureWhite, padding: spacing.lg, borderRadius: radius.lg, marginTop: spacing.sm, borderWidth: 1, borderColor: colors.birch },
  featureRow: { flexDirection: "row", alignItems: "center", gap: spacing.sm, paddingVertical: 6 },
  featureText: { fontFamily: fonts.bodyMed, fontSize: 14, color: colors.ink2 },
  payBtn: { backgroundColor: colors.imperialGold, paddingVertical: 16, borderRadius: radius.md, alignItems: "center", marginTop: spacing.lg, ...shadow.gold },
  payText: { fontFamily: fonts.bodyBold, fontSize: 16, color: colors.pureWhite, letterSpacing: 0.5 },
  disclaimer: { fontFamily: fonts.body, fontSize: 11, color: colors.ink4, textAlign: "center", marginTop: spacing.md, lineHeight: 16 },
});
