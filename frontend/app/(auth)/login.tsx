import React, { useState } from "react";
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  ActivityIndicator,
  Alert,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Link } from "expo-router";
import { colors, fonts, spacing, radius, shadow } from "@/src/theme";
import CrownLogo from "@/src/components/CrownLogo";
import { useAuth } from "@/src/context/AuthContext";

export default function Login() {
  const { login } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const onSubmit = async () => {
    if (!email || !password) {
      setErr("Enter email and password");
      return;
    }
    setErr(null);
    setBusy(true);
    try {
      await login(email.trim().toLowerCase(), password);
    } catch (e: any) {
      setErr(e.message || "Login failed");
    } finally {
      setBusy(false);
    }
  };

  return (
    <SafeAreaView style={styles.safe} edges={["top", "bottom"]}>
      <KeyboardAvoidingView behavior={Platform.OS === "ios" ? "padding" : undefined} style={{ flex: 1 }}>
        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
          <View style={styles.logoWrap}>
            <CrownLogo size={72} />
          </View>
          <Text style={styles.brand}>Trading Titans</Text>
          <Text style={styles.tagline}>Trade Bold. Lose Nothing.</Text>

          <View style={styles.card}>
            <Text style={styles.title}>Welcome back, Titan</Text>
            <Text style={styles.subtitle}>Sign in to your trading desk</Text>

            <Text style={styles.label}>Email</Text>
            <TextInput
              testID="login-email-input"
              value={email}
              onChangeText={setEmail}
              autoCapitalize="none"
              keyboardType="email-address"
              placeholder="you@example.com"
              placeholderTextColor={colors.ink5}
              style={styles.input}
            />

            <Text style={styles.label}>Password</Text>
            <TextInput
              testID="login-password-input"
              value={password}
              onChangeText={setPassword}
              secureTextEntry
              placeholder="••••••••"
              placeholderTextColor={colors.ink5}
              style={styles.input}
            />

            {err && (
              <Text testID="login-error" style={styles.error}>
                {err}
              </Text>
            )}

            <TouchableOpacity
              testID="login-submit-button"
              style={[styles.primaryBtn, busy && { opacity: 0.7 }]}
              onPress={onSubmit}
              disabled={busy}
              activeOpacity={0.85}
            >
              {busy ? <ActivityIndicator color={colors.parchment} /> : <Text style={styles.primaryBtnText}>Sign In</Text>}
            </TouchableOpacity>

            <View style={styles.footer}>
              <Text style={styles.footerText}>New to the desk?</Text>
              <Link href="/(auth)/register" asChild>
                <TouchableOpacity testID="goto-register-link">
                  <Text style={styles.footerLink}> Create account</Text>
                </TouchableOpacity>
              </Link>
            </View>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.parchment },
  scroll: { padding: spacing.lg, paddingTop: spacing.xxl, flexGrow: 1 },
  logoWrap: { alignItems: "center", marginBottom: spacing.sm },
  brand: {
    textAlign: "center",
    fontFamily: fonts.displayBlack,
    fontSize: 32,
    color: colors.ink,
    letterSpacing: 0.5,
  },
  tagline: {
    textAlign: "center",
    fontFamily: fonts.displayItalic,
    fontSize: 15,
    color: colors.goldDeep,
    marginTop: 4,
    marginBottom: spacing.xl,
  },
  card: {
    backgroundColor: colors.pureWhite,
    borderRadius: radius.xl,
    padding: spacing.xl,
    borderWidth: 1,
    borderColor: colors.birch,
    ...shadow.md,
  },
  title: { fontFamily: fonts.display, fontSize: 24, color: colors.ink },
  subtitle: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4, marginTop: 4, marginBottom: spacing.lg },
  label: { fontFamily: fonts.bodyMed, fontSize: 12, color: colors.ink3, marginBottom: 6, marginTop: spacing.md },
  input: {
    backgroundColor: colors.cream,
    borderWidth: 1,
    borderColor: colors.birch,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: 12,
    fontFamily: fonts.body,
    fontSize: 15,
    color: colors.ink,
  },
  error: { fontFamily: fonts.body, fontSize: 13, color: colors.bear, marginTop: spacing.sm },
  primaryBtn: {
    marginTop: spacing.xl,
    backgroundColor: colors.imperialGold,
    paddingVertical: 14,
    borderRadius: radius.md,
    alignItems: "center",
    ...shadow.gold,
  },
  primaryBtnText: { color: colors.parchment, fontFamily: fonts.bodyBold, fontSize: 15, letterSpacing: 0.5 },
  footer: { flexDirection: "row", justifyContent: "center", marginTop: spacing.lg },
  footerText: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4 },
  footerLink: { fontFamily: fonts.bodyBold, fontSize: 13, color: colors.imperialGold },
});
