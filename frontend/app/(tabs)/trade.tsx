import React, { useCallback, useEffect, useState } from "react";
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  FlatList,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useRouter } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts, spacing, radius, shadow } from "@/src/theme";
import { api, SearchItem } from "@/src/api/client";

const POPULAR_STOCKS: SearchItem[] = [
  { symbol: "RELIANCE", name: "Reliance Industries", market: "stock" },
  { symbol: "TCS", name: "Tata Consultancy Services", market: "stock" },
  { symbol: "HDFCBANK", name: "HDFC Bank", market: "stock" },
  { symbol: "INFY", name: "Infosys", market: "stock" },
  { symbol: "ICICIBANK", name: "ICICI Bank", market: "stock" },
  { symbol: "TATAMOTORS", name: "Tata Motors", market: "stock" },
  { symbol: "ADANIENT", name: "Adani Enterprises", market: "stock" },
  { symbol: "ZOMATO", name: "Zomato", market: "stock" },
];

const POPULAR_CRYPTO: SearchItem[] = [
  { symbol: "BTC", name: "Bitcoin", market: "crypto" },
  { symbol: "ETH", name: "Ethereum", market: "crypto" },
  { symbol: "SOL", name: "Solana", market: "crypto" },
  { symbol: "BNB", name: "BNB", market: "crypto" },
  { symbol: "XRP", name: "Ripple", market: "crypto" },
  { symbol: "ADA", name: "Cardano", market: "crypto" },
  { symbol: "DOGE", name: "Dogecoin", market: "crypto" },
  { symbol: "MATIC", name: "Polygon", market: "crypto" },
];

export default function Trade() {
  const router = useRouter();
  const [market, setMarket] = useState<"stock" | "crypto">("stock");
  const [q, setQ] = useState("");
  const [results, setResults] = useState<SearchItem[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!q.trim()) {
      setResults([]);
      return;
    }
    setLoading(true);
    const handle = setTimeout(async () => {
      try {
        const r = await api.search(q.trim(), market);
        setResults(r);
      } catch (e) {
        console.warn(e);
      } finally {
        setLoading(false);
      }
    }, 350);
    return () => clearTimeout(handle);
  }, [q, market]);

  const popular = market === "stock" ? POPULAR_STOCKS : POPULAR_CRYPTO;
  const shownItems = q.trim() ? results : popular;

  return (
    <SafeAreaView style={styles.safe} edges={["top"]}>
      <KeyboardAvoidingView behavior={Platform.OS === "ios" ? "padding" : undefined} style={{ flex: 1 }}>
        <View style={styles.header}>
          <Text style={styles.title}>Trade</Text>
          <Text style={styles.subtitle}>Real markets. Virtual stakes.</Text>
        </View>

        {/* Market toggle */}
        <View style={styles.tabs}>
          <TouchableOpacity
            testID="market-tab-stock"
            style={[styles.tab, market === "stock" && styles.tabActive]}
            onPress={() => {
              setMarket("stock");
              setQ("");
            }}
          >
            <Text style={[styles.tabText, market === "stock" && styles.tabTextActive]}>Indian Stocks</Text>
          </TouchableOpacity>
          <TouchableOpacity
            testID="market-tab-crypto"
            style={[styles.tab, market === "crypto" && styles.tabActive]}
            onPress={() => {
              setMarket("crypto");
              setQ("");
            }}
          >
            <Text style={[styles.tabText, market === "crypto" && styles.tabTextActive]}>Crypto</Text>
          </TouchableOpacity>
        </View>

        {/* Search */}
        <View style={styles.searchWrap}>
          <Ionicons name="search" size={18} color={colors.ink4} />
          <TextInput
            testID="search-input"
            value={q}
            onChangeText={setQ}
            placeholder={market === "stock" ? "Search NSE stocks…" : "Search crypto…"}
            placeholderTextColor={colors.ink5}
            autoCapitalize="none"
            style={styles.searchInput}
          />
          {loading && <ActivityIndicator size="small" color={colors.imperialGold} />}
        </View>

        {!q.trim() && (
          <Text style={styles.sectionLabel}>{market === "stock" ? "Popular Stocks" : "Top Crypto"}</Text>
        )}

        <FlatList
          data={shownItems}
          keyExtractor={(it) => `${it.symbol}-${it.market}`}
          contentContainerStyle={{ padding: spacing.lg, paddingTop: 0 }}
          renderItem={({ item }) => (
            <TouchableOpacity
              testID={`asset-row-${item.symbol}`}
              style={styles.row}
              onPress={() =>
                router.push({ pathname: "/stock/[symbol]", params: { symbol: item.symbol, market: item.market, name: item.name } })
              }
            >
              <View style={styles.avatar}>
                <Text style={styles.avatarText}>{item.symbol.slice(0, 2)}</Text>
              </View>
              <View style={{ flex: 1 }}>
                <Text style={styles.rowSym}>{item.symbol}</Text>
                <Text style={styles.rowName} numberOfLines={1}>{item.name}</Text>
              </View>
              <Ionicons name="chevron-forward" size={18} color={colors.ink4} />
            </TouchableOpacity>
          )}
          ListEmptyComponent={
            q.trim() && !loading ? (
              <Text style={styles.empty}>No results for "{q}"</Text>
            ) : null
          }
        />
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  header: { paddingHorizontal: spacing.lg, paddingTop: spacing.md },
  title: { fontFamily: fonts.displayBlack, fontSize: 28, color: colors.ink },
  subtitle: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4, marginTop: 2 },
  tabs: { flexDirection: "row", marginHorizontal: spacing.lg, marginTop: spacing.md, backgroundColor: colors.cream, borderRadius: radius.md, padding: 4, borderWidth: 1, borderColor: colors.birch },
  tab: { flex: 1, paddingVertical: 10, borderRadius: radius.sm, alignItems: "center" },
  tabActive: { backgroundColor: colors.pureWhite, ...shadow.sm },
  tabText: { fontFamily: fonts.bodyMed, fontSize: 13, color: colors.ink4 },
  tabTextActive: { color: colors.ink },
  searchWrap: {
    flexDirection: "row",
    alignItems: "center",
    marginHorizontal: spacing.lg,
    marginTop: spacing.md,
    backgroundColor: colors.pureWhite,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    borderWidth: 1,
    borderColor: colors.birch,
    gap: spacing.sm,
  },
  searchInput: { flex: 1, paddingVertical: 12, fontFamily: fonts.body, fontSize: 15, color: colors.ink },
  sectionLabel: { fontFamily: fonts.bodyMed, fontSize: 12, color: colors.ink4, paddingHorizontal: spacing.lg, marginTop: spacing.lg, marginBottom: spacing.sm, textTransform: "uppercase", letterSpacing: 0.5 },
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
  avatar: { width: 40, height: 40, borderRadius: radius.pill, backgroundColor: colors.goldPale, alignItems: "center", justifyContent: "center", borderWidth: 1, borderColor: colors.goldBorder },
  avatarText: { fontFamily: fonts.bodyBold, fontSize: 12, color: colors.goldDeep },
  rowSym: { fontFamily: fonts.bodyBold, fontSize: 14, color: colors.ink },
  rowName: { fontFamily: fonts.body, fontSize: 12, color: colors.ink4, marginTop: 2 },
  empty: { fontFamily: fonts.body, fontSize: 14, color: colors.ink4, textAlign: "center", marginTop: spacing.xl },
});
