import React, { useState } from "react";
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  ScrollView,
  Alert,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useRouter } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, shadow, formatINR, formatPct } from "@/src/theme";
import { api } from "@/src/api/client";

export default function WhatIf() {
  const router = useRouter();
  const [symbol, setSymbol] = useState("RELIANCE");
  const [market, setMarket] = useState<"stock" | "crypto">("stock");
  const [amount, setAmount] = useState("10000");
  const [years, setYears] = useState("5");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<any>(null);

  const run = async () => {
    if (!symbol || !amount || !years) {
      Alert.alert("Missing fields", "Fill all fields");
      return;
    }
    setBusy(true);
    setResult(null);
    try {
      const r = await api.whatIf(symbol.toUpperCase(), market, parseFloat(amount), parseFloat(years));
      setResult(r);
    } catch (e: any) {
      Alert.alert("Failed", e.message || "Could not compute");
    } finally {
      setBusy(false);
    }
  };

  const profit = result && result.pnl >= 0;

  return (
    <SafeAreaView style={styles.safe} edges={["top"]}>
      <KeyboardAvoidingView behavior={Platform.OS === "ios" ? "padding" : undefined} style={{ flex: 1 }}>
        <View style={styles.header}>
          <TouchableOpacity testID="whatif-back" onPress={() => router.back()} style={styles.iconBtn}>
            <Ionicons name="chevron-back" size={22} color={colors.ink} />
          </TouchableOpacity>
          <Text style={styles.title}>What-If Simulator</Text>
          <View style={{ width: 40 }} />
        </View>

        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
          <View style={styles.card}>
            <Text style={styles.sub}>If I had invested in… how much would I have today?</Text>

            <View style={styles.tabs}>
              <TouchableOpacity testID="whatif-tab-stock" style={[styles.tab, market === "stock" && styles.tabActive]} onPress={() => setMarket("stock")}>
                <Text style={[styles.tabText, market === "stock" && styles.tabTextActive]}>Stock</Text>
              </TouchableOpacity>
              <TouchableOpacity testID="whatif-tab-crypto" style={[styles.tab, market === "crypto" && styles.tabActive]} onPress={() => setMarket("crypto")}>
                <Text style={[styles.tabText, market === "crypto" && styles.tabTextActive]}>Crypto</Text>
              </TouchableOpacity>
            </View>

            <Text style={styles.label}>Symbol</Text>
            <TextInput
              testID="whatif-symbol"
              value={symbol}
              onChangeText={setSymbol}
              autoCapitalize="characters"
              placeholder={market === "stock" ? "RELIANCE, TCS…" : "BTC, ETH…"}
              placeholderTextColor={colors.ink5}
              style={styles.input}
            />

            <Text style={styles.label}>Amount (₹)</Text>
            <TextInput
              testID="whatif-amount"
              value={amount}
              onChangeText={setAmount}
              keyboardType="numeric"
              placeholderTextColor={colors.ink5}
              style={styles.input}
            />

            <Text style={styles.label}>Years Ago</Text>
            <TextInput
              testID="whatif-years"
              value={years}
              onChangeText={setYears}
              keyboardType="decimal-pad"
              placeholderTextColor={colors.ink5}
              style={styles.input}
            />

            <TouchableOpacity testID="whatif-run" style={[styles.runBtn, busy && { opacity: 0.7 }]} onPress={run} disabled={busy}>
              {busy ? <ActivityIndicator color={colors.parchment} /> : <Text style={styles.runText}>Calculate</Text>}
            </TouchableOpacity>
          </View>

          {result && (
            <View style={[styles.resultCard, { borderColor: profit ? colors.bull : colors.bear }]}>
              <Text style={styles.resultLabel}>If you had invested {formatINR(result.amount_invested, 0)} in {result.symbol}…</Text>
              <Text style={[styles.bigPnl, { color: profit ? colors.bull : colors.bear }]}>
                {formatINR(result.current_value, 0)}
              </Text>
              <Text style={[styles.pnlText, { color: profit ? colors.bull : colors.bear }]}>
                {formatINR(result.pnl, 0)} ({formatPct(result.pnl_pct)})
              </Text>

              <View style={styles.divider} />

              <View style={styles.resRow}>
                <Text style={styles.resLabel}>Purchase Price</Text>
                <Text style={styles.resVal}>{formatINR(result.purchase_price)}</Text>
              </View>
              <View style={styles.resRow}>
                <Text style={styles.resLabel}>Current Price</Text>
                <Text style={styles.resVal}>{formatINR(result.current_price)}</Text>
              </View>
              <View style={styles.resRow}>
                <Text style={styles.resLabel}>Units Held</Text>
                <Text style={styles.resVal}>{result.units.toFixed(4)}</Text>
              </View>
            </View>
          )}
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  header: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingHorizontal: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.sm },
  iconBtn: { width: 40, height: 40, borderRadius: radius.pill, backgroundColor: colors.cream, alignItems: "center", justifyContent: "center", borderWidth: 1, borderColor: colors.birch },
  title: { fontFamily: fonts.display, fontSize: 18, color: colors.ink },
  scroll: { padding: spacing.lg },
  card: { backgroundColor: colors.pureWhite, padding: spacing.lg, borderRadius: radius.xl, borderWidth: 1, borderColor: colors.birch, ...shadow.md },
  sub: { fontFamily: fonts.displayItalic, fontSize: 14, color: colors.goldDeep, marginBottom: spacing.md },
  tabs: { flexDirection: "row", backgroundColor: colors.cream, borderRadius: radius.md, padding: 4, borderWidth: 1, borderColor: colors.birch },
  tab: { flex: 1, paddingVertical: 8, alignItems: "center", borderRadius: radius.sm },
  tabActive: { backgroundColor: colors.pureWhite, ...shadow.sm },
  tabText: { fontFamily: fonts.bodyMed, fontSize: 13, color: colors.ink4 },
  tabTextActive: { color: colors.ink },
  label: { fontFamily: fonts.bodyMed, fontSize: 12, color: colors.ink3, marginTop: spacing.md, marginBottom: 6 },
  input: { backgroundColor: colors.cream, borderWidth: 1, borderColor: colors.birch, borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: 12, fontFamily: fonts.body, fontSize: 15, color: colors.ink },
  runBtn: { marginTop: spacing.lg, backgroundColor: colors.imperialGold, paddingVertical: 14, borderRadius: radius.md, alignItems: "center", ...shadow.gold },
  runText: { fontFamily: fonts.bodyBold, fontSize: 15, color: colors.parchment, letterSpacing: 0.5 },
  resultCard: { marginTop: spacing.lg, backgroundColor: colors.warmWhite, borderRadius: radius.xl, padding: spacing.xl, borderWidth: 2, ...shadow.md },
  resultLabel: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4 },
  bigPnl: { fontFamily: fonts.displayBlack, fontSize: 36, marginTop: spacing.sm, letterSpacing: -0.5 },
  pnlText: { fontFamily: fonts.monoMed, fontSize: 14, marginTop: 2 },
  divider: { height: 1, backgroundColor: colors.birch, marginVertical: spacing.lg },
  resRow: { flexDirection: "row", justifyContent: "space-between", paddingVertical: 6 },
  resLabel: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4 },
  resVal: { fontFamily: fonts.monoMed, fontSize: 13, color: colors.ink },
});
