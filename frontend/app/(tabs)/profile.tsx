import React, { useCallback, useState } from "react";
import { View, Text, StyleSheet, TouchableOpacity, Alert, ScrollView, Linking } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useRouter, useFocusEffect } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, shadow } from "@/src/theme";
import { useAuth } from "@/src/context/AuthContext";
import { api } from "@/src/api/client";
import CrownLogo from "@/src/components/CrownLogo";

export default function Profile() {
  const { user, logout } = useAuth();
  const router = useRouter();
  const [upstox, setUpstox] = useState<any>(null);

  const loadUpstox = useCallback(async () => {
    try {
      const s = await api.upstoxStatus();
      setUpstox(s);
    } catch {}
  }, []);

  useFocusEffect(useCallback(() => { loadUpstox(); }, [loadUpstox]));

  const connectUpstox = async () => {
    try {
      const { auth_url } = await api.upstoxAuthUrl();
      Alert.alert(
        "Connect Upstox",
        "You'll be sent to Upstox to log in. After approving, real-time NSE/BSE data will activate (until 3:30 AM IST tomorrow).",
        [
          { text: "Cancel", style: "cancel" },
          { text: "Open Upstox", onPress: () => Linking.openURL(auth_url) },
        ]
      );
    } catch (e: any) {
      Alert.alert("Failed", e.message || "Could not start Upstox login");
    }
  };

  const confirmLogout = () => {
    Alert.alert("Sign out", "Are you sure?", [
      { text: "Cancel", style: "cancel" },
      { text: "Sign out", style: "destructive", onPress: logout },
    ]);
  };

  return (
    <SafeAreaView style={styles.safe} edges={["top"]}>
      <ScrollView contentContainerStyle={{ padding: spacing.lg, paddingBottom: spacing.xxl }}>
        <View style={styles.profileCard}>
          <CrownLogo size={56} />
          <Text style={styles.name}>{user?.name}</Text>
          <Text style={styles.email}>{user?.email}</Text>
          <View style={styles.tierBadge}>
            <Ionicons name="ribbon" size={14} color={colors.imperialGold} />
            <Text style={styles.tierText}>FREE STARTER · ₹1L</Text>
          </View>
        </View>

        {/* Upstox status (real-time data source) */}
        <Text style={styles.section}>Data Source</Text>
        <View style={[styles.upstoxCard, upstox?.authorized && { borderColor: colors.bull, backgroundColor: colors.bullLight }]}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: spacing.sm }}>
            <View style={[styles.statusDot, { backgroundColor: upstox?.authorized ? colors.bull : colors.ink5 }]} />
            <View style={{ flex: 1 }}>
              <Text style={styles.upstoxTitle}>Upstox NSE/BSE Real-Time</Text>
              <Text style={styles.upstoxSub}>
                {upstox?.authorized
                  ? `Active · expires in ${Math.floor((upstox.remaining_seconds || 0) / 3600)}h`
                  : "Not connected · using delayed Yahoo Finance fallback"}
              </Text>
            </View>
          </View>
          <TouchableOpacity testID="upstox-connect" style={styles.upstoxBtn} onPress={connectUpstox}>
            <Text style={styles.upstoxBtnText}>{upstox?.authorized ? "Reconnect" : "Connect"}</Text>
          </TouchableOpacity>
        </View>

        <Text style={styles.section}>Tools</Text>
        <MenuRow icon="stats-chart-outline" label="Analytics" testID="menu-analytics" onPress={() => router.push("/analytics")} />
        <MenuRow icon="receipt-outline" label="Order History" testID="menu-orders" onPress={() => router.push("/orders")} />
        <MenuRow icon="bulb-outline" label="What-If Simulator" testID="menu-whatif" onPress={() => router.push("/whatif")} />
        <MenuRow icon="medkit-outline" label="Loss Autopsy" testID="menu-autopsy" onPress={() => router.push("/autopsy")} />

        <Text style={styles.section}>Wallet</Text>
        <MenuRow icon="add-circle-outline" label="Top-up Demo Cash" testID="menu-topup" onPress={() => router.push("/subscribe")} gold />
        <MenuRow icon="log-out-outline" label="Sign Out" testID="menu-logout" onPress={confirmLogout} danger />

        <Text style={styles.footer}>Trading Titans · v1.1 · Real Market. Virtual Risk.</Text>
      </ScrollView>
    </SafeAreaView>
  );
}

function MenuRow({ icon, label, onPress, danger, gold, testID }: { icon: any; label: string; onPress: () => void; danger?: boolean; gold?: boolean; testID?: string }) {
  return (
    <TouchableOpacity testID={testID} style={[styles.row, gold && styles.rowGold]} onPress={onPress} activeOpacity={0.8}>
      <View style={[styles.iconBox, gold && { backgroundColor: colors.imperialGold }]}>
        <Ionicons name={icon} size={20} color={gold ? colors.pureWhite : danger ? colors.bear : colors.ink3} />
      </View>
      <Text style={[styles.rowLabel, danger && { color: colors.bear }, gold && { color: colors.goldDeep, fontFamily: fonts.bodyBold }]}>
        {label}
      </Text>
      <Ionicons name="chevron-forward" size={18} color={colors.ink4} />
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  profileCard: { backgroundColor: colors.pureWhite, borderRadius: radius.xl, padding: spacing.xl, alignItems: "center", borderWidth: 1, borderColor: colors.birch, ...shadow.md },
  name: { fontFamily: fonts.display, fontSize: 22, color: colors.ink, marginTop: spacing.sm },
  email: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4, marginTop: 2 },
  tierBadge: { flexDirection: "row", alignItems: "center", gap: 4, backgroundColor: colors.goldPale, paddingHorizontal: spacing.sm, paddingVertical: 4, borderRadius: radius.pill, marginTop: spacing.sm, borderWidth: 1, borderColor: colors.goldBorder },
  tierText: { fontFamily: fonts.bodyBold, fontSize: 10, color: colors.goldDeep, letterSpacing: 1 },
  section: { fontFamily: fonts.display, fontSize: 16, color: colors.ink, marginTop: spacing.xl, marginBottom: spacing.sm },
  upstoxCard: { backgroundColor: colors.pureWhite, padding: spacing.lg, borderRadius: radius.lg, borderWidth: 1, borderColor: colors.birch, marginBottom: spacing.sm },
  statusDot: { width: 10, height: 10, borderRadius: radius.pill },
  upstoxTitle: { fontFamily: fonts.bodyBold, fontSize: 14, color: colors.ink },
  upstoxSub: { fontFamily: fonts.body, fontSize: 12, color: colors.ink4, marginTop: 2 },
  upstoxBtn: { marginTop: spacing.sm, alignSelf: "flex-start", backgroundColor: colors.imperialGold, paddingVertical: 8, paddingHorizontal: spacing.md, borderRadius: radius.sm },
  upstoxBtnText: { fontFamily: fonts.bodyBold, fontSize: 12, color: colors.pureWhite, letterSpacing: 0.5 },
  row: { flexDirection: "row", alignItems: "center", backgroundColor: colors.warmWhite, paddingHorizontal: spacing.md, paddingVertical: 14, borderRadius: radius.md, borderWidth: 1, borderColor: colors.birch, marginBottom: spacing.sm, gap: spacing.md },
  rowGold: { backgroundColor: colors.goldPale, borderColor: colors.goldBorder },
  iconBox: { width: 32, height: 32, borderRadius: radius.pill, backgroundColor: colors.cream, alignItems: "center", justifyContent: "center" },
  rowLabel: { flex: 1, fontFamily: fonts.bodyMed, fontSize: 14, color: colors.ink },
  footer: { fontFamily: fonts.body, fontSize: 12, color: colors.ink4, textAlign: "center", marginTop: spacing.xl, fontStyle: "italic" },
});
