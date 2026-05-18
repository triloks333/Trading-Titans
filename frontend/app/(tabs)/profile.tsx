import React from "react";
import { View, Text, StyleSheet, TouchableOpacity, Alert, ScrollView } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useRouter } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, shadow } from "@/src/theme";
import { useAuth } from "@/src/context/AuthContext";
import CrownLogo from "@/src/components/CrownLogo";

export default function Profile() {
  const { user, logout } = useAuth();
  const router = useRouter();

  const confirmLogout = () => {
    Alert.alert("Sign out", "Are you sure you want to sign out?", [
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
          {user?.subscription_active && (
            <View style={styles.tierBadge}>
              <Ionicons name="ribbon" size={14} color={colors.goldDeep} />
              <Text style={styles.tierText}>TITAN MEMBER</Text>
            </View>
          )}
        </View>

        <Text style={styles.section}>Tools</Text>
        <MenuRow icon="stats-chart-outline" label="Analytics" testID="menu-analytics" onPress={() => router.push("/analytics")} />
        <MenuRow icon="receipt-outline" label="Order History" testID="menu-orders" onPress={() => router.push("/orders")} />
        <MenuRow icon="bulb-outline" label="What-If Simulator" testID="menu-whatif" onPress={() => router.push("/whatif")} />
        <MenuRow icon="medkit-outline" label="Loss Autopsy" testID="menu-autopsy" onPress={() => router.push("/autopsy")} />

        <Text style={styles.section}>Account</Text>
        {!user?.subscription_active && (
          <MenuRow icon="ribbon-outline" label="Activate Titan Plan" testID="menu-subscribe" onPress={() => router.push("/subscribe")} gold />
        )}
        <MenuRow icon="log-out-outline" label="Sign Out" testID="menu-logout" onPress={confirmLogout} danger />

        <Text style={styles.footer}>Trading Titans · v1.0 · Real Market. Virtual Risk.</Text>
      </ScrollView>
    </SafeAreaView>
  );
}

function MenuRow({ icon, label, onPress, danger, gold, testID }: { icon: any; label: string; onPress: () => void; danger?: boolean; gold?: boolean; testID?: string }) {
  return (
    <TouchableOpacity testID={testID} style={[styles.row, gold && styles.rowGold]} onPress={onPress} activeOpacity={0.8}>
      <View style={[styles.iconBox, gold && { backgroundColor: colors.imperialGold }]}>
        <Ionicons name={icon} size={20} color={gold ? colors.parchment : danger ? colors.bear : colors.ink3} />
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
  profileCard: {
    backgroundColor: colors.pureWhite,
    borderRadius: radius.xl,
    padding: spacing.xl,
    alignItems: "center",
    borderWidth: 1,
    borderColor: colors.birch,
    ...shadow.md,
  },
  name: { fontFamily: fonts.display, fontSize: 22, color: colors.ink, marginTop: spacing.sm },
  email: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4, marginTop: 2 },
  tierBadge: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    backgroundColor: colors.goldPale,
    paddingHorizontal: spacing.sm,
    paddingVertical: 4,
    borderRadius: radius.pill,
    marginTop: spacing.sm,
    borderWidth: 1,
    borderColor: colors.goldBorder,
  },
  tierText: { fontFamily: fonts.bodyBold, fontSize: 10, color: colors.goldDeep, letterSpacing: 1 },
  section: { fontFamily: fonts.display, fontSize: 16, color: colors.ink, marginTop: spacing.xl, marginBottom: spacing.sm },
  row: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: colors.warmWhite,
    paddingHorizontal: spacing.md,
    paddingVertical: 14,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.birch,
    marginBottom: spacing.sm,
    gap: spacing.md,
  },
  rowGold: { backgroundColor: colors.goldPale, borderColor: colors.goldBorder },
  iconBox: { width: 32, height: 32, borderRadius: radius.pill, backgroundColor: colors.cream, alignItems: "center", justifyContent: "center" },
  rowLabel: { flex: 1, fontFamily: fonts.bodyMed, fontSize: 14, color: colors.ink },
  footer: { fontFamily: fonts.displayItalic, fontSize: 12, color: colors.ink4, textAlign: "center", marginTop: spacing.xl },
});
