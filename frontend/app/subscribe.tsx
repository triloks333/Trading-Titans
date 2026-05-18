import React, { useState } from "react";
import { View, Text, StyleSheet, TouchableOpacity, ScrollView, Alert, ActivityIndicator } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useRouter } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, shadow } from "@/src/theme";
import CrownLogo from "@/src/components/CrownLogo";
import { api } from "@/src/api/client";
import { useAuth } from "@/src/context/AuthContext";

const FEATURES = [
  { icon: "wallet-outline", text: "₹1,00,000 demo cash credited instantly" },
  { icon: "trending-up-outline", text: "Real-time NSE/BSE stocks + Crypto" },
  { icon: "infinite-outline", text: "Unlimited trades · No slippage" },
  { icon: "bulb-outline", text: "What-If simulator + Loss Autopsy" },
  { icon: "trophy-outline", text: "Weekly Leagues + Leaderboard" },
];

export default function Subscribe() {
  const router = useRouter();
  const { refreshUser, user } = useAuth();
  const [busy, setBusy] = useState(false);

  const onPay = async () => {
    if (user?.subscription_active) {
      Alert.alert("Already a Titan", "Your Titan Plan is active.");
      return;
    }
    setBusy(true);
    try {
      // Step 1: create order (real Razorpay would return order_id+key)
      const order = await api.createSubscriptionOrder();
      // Step 2: in production this would open Razorpay Checkout via WebView/SDK
      // For now, demo flow: confirm and activate
      Alert.alert(
        "Confirm payment",
        order.is_mock
          ? "Razorpay test/demo mode — confirm to activate Titan Plan (₹199)."
          : "Open Razorpay checkout to pay ₹199.",
        [
          { text: "Cancel", style: "cancel", onPress: () => setBusy(false) },
          {
            text: "Pay ₹199",
            onPress: async () => {
              try {
                const r = await api.activateSubscription({ order_id: order.id });
                await refreshUser();
                Alert.alert("Welcome, Titan!", r.message, [
                  { text: "Start Trading", onPress: () => router.replace("/(tabs)/dashboard") },
                ]);
              } catch (e: any) {
                Alert.alert("Payment failed", e.message || "Try again");
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
        <View style={styles.crownWrap}>
          <CrownLogo size={88} />
        </View>
        <Text style={styles.brand}>Titan Plan</Text>
        <Text style={styles.tagline}>Real Market. Virtual Risk.</Text>

        <View style={styles.priceCard}>
          <Text style={styles.priceLabel}>One-time activation</Text>
          <View style={styles.priceRow}>
            <Text style={styles.currency}>₹</Text>
            <Text style={styles.price}>199</Text>
            <Text style={styles.unit}>/ unlock</Text>
          </View>
          <Text style={styles.priceSub}>Get ₹1,00,000 demo cash · Real markets · No real risk</Text>
        </View>

        <View style={styles.featuresCard}>
          {FEATURES.map((f, i) => (
            <View key={i} style={styles.featureRow}>
              <View style={styles.featureIcon}>
                <Ionicons name={f.icon as any} size={18} color={colors.goldDeep} />
              </View>
              <Text style={styles.featureText}>{f.text}</Text>
            </View>
          ))}
        </View>

        <TouchableOpacity testID="pay-button" style={[styles.payBtn, busy && { opacity: 0.7 }]} onPress={onPay} disabled={busy}>
          {busy ? <ActivityIndicator color={colors.parchment} /> : <Text style={styles.payText}>Pay ₹199 via Razorpay</Text>}
        </TouchableOpacity>

        <Text style={styles.disclaimer}>
          Powered by Razorpay · Secure UPI/Card payments. Demo cash is virtual and has no real-world value.
        </Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  header: { flexDirection: "row", justifyContent: "space-between", paddingHorizontal: spacing.lg, paddingTop: spacing.sm },
  iconBtn: { width: 40, height: 40, borderRadius: radius.pill, backgroundColor: colors.cream, alignItems: "center", justifyContent: "center", borderWidth: 1, borderColor: colors.birch },
  scroll: { padding: spacing.lg, paddingBottom: spacing.xxl, alignItems: "stretch" },
  crownWrap: { alignItems: "center", marginTop: spacing.md },
  brand: { textAlign: "center", fontFamily: fonts.displayBlack, fontSize: 32, color: colors.ink, marginTop: spacing.sm },
  tagline: { textAlign: "center", fontFamily: fonts.displayItalic, fontSize: 14, color: colors.goldDeep, marginTop: 4, marginBottom: spacing.lg },
  priceCard: { backgroundColor: colors.ink, padding: spacing.xl, borderRadius: radius.xl, alignItems: "center", borderWidth: 1, borderColor: colors.goldBorder, ...shadow.gold },
  priceLabel: { fontFamily: fonts.bodyMed, fontSize: 11, color: colors.goldLight, letterSpacing: 1, textTransform: "uppercase" },
  priceRow: { flexDirection: "row", alignItems: "baseline", marginTop: spacing.sm },
  currency: { fontFamily: fonts.display, fontSize: 24, color: colors.goldLight },
  price: { fontFamily: fonts.displayBlack, fontSize: 56, color: colors.goldLight, letterSpacing: -2 },
  unit: { fontFamily: fonts.body, fontSize: 13, color: colors.parchment, marginLeft: 4 },
  priceSub: { fontFamily: fonts.body, fontSize: 13, color: colors.parchment, marginTop: spacing.sm, textAlign: "center" },
  featuresCard: { backgroundColor: colors.pureWhite, padding: spacing.lg, borderRadius: radius.xl, marginTop: spacing.md, borderWidth: 1, borderColor: colors.birch },
  featureRow: { flexDirection: "row", alignItems: "center", gap: spacing.md, paddingVertical: spacing.sm },
  featureIcon: { width: 32, height: 32, borderRadius: radius.pill, backgroundColor: colors.goldPale, alignItems: "center", justifyContent: "center", borderWidth: 1, borderColor: colors.goldBorder },
  featureText: { flex: 1, fontFamily: fonts.bodyMed, fontSize: 14, color: colors.ink2 },
  payBtn: { backgroundColor: colors.imperialGold, paddingVertical: 16, borderRadius: radius.md, alignItems: "center", marginTop: spacing.lg, ...shadow.gold },
  payText: { fontFamily: fonts.bodyBold, fontSize: 16, color: colors.parchment, letterSpacing: 0.5 },
  disclaimer: { fontFamily: fonts.body, fontSize: 11, color: colors.ink4, textAlign: "center", marginTop: spacing.md, lineHeight: 16 },
});
