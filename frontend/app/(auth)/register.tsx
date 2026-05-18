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
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Link } from "expo-router";
import { colors, fonts, spacing, radius, shadow } from "@/src/theme";
import CrownLogo from "@/src/components/CrownLogo";
import { useAuth } from "@/src/context/AuthContext";

export default function Register() {
  const { register } = useAuth();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const onSubmit = async () => {
    if (!name || !email || !password) {
      setErr("All fields required");
      return;
    }
    if (password.length < 6) {
      setErr("Password must be at least 6 characters");
      return;
    }
    setErr(null);
    setBusy(true);
    try {
      await register(email.trim().toLowerCase(), password, name.trim());
    } catch (e: any) {
      setErr(e.message || "Registration failed");
    } finally {
      setBusy(false);
    }
  };

  return (
    <SafeAreaView style={styles.safe} edges={["top", "bottom"]}>
      <KeyboardAvoidingView behavior={Platform.OS === "ios" ? "padding" : undefined} style={{ flex: 1 }}>
        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
          <View style={styles.logoWrap}>
            <CrownLogo size={64} />
          </View>
          <Text style={styles.brand}>Join the Titans</Text>
          <Text style={styles.tagline}>Real Market. Virtual Risk.</Text>

          <View style={styles.card}>
            <Text style={styles.title}>Create your desk</Text>
            <Text style={styles.subtitle}>Start with ₹0 — unlock ₹1,00,000 with Titan Plan</Text>

            <Text style={styles.label}>Full Name</Text>
            <TextInput
              testID="register-name-input"
              value={name}
              onChangeText={setName}
              placeholder="Arjun Mehra"
              placeholderTextColor={colors.ink5}
              style={styles.input}
            />

            <Text style={styles.label}>Email</Text>
            <TextInput
              testID="register-email-input"
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
              testID="register-password-input"
              value={password}
              onChangeText={setPassword}
              secureTextEntry
              placeholder="At least 6 characters"
              placeholderTextColor={colors.ink5}
              style={styles.input}
            />

            {err && (
              <Text testID="register-error" style={styles.error}>
                {err}
              </Text>
            )}

            <TouchableOpacity
              testID="register-submit-button"
              style={[styles.primaryBtn, busy && { opacity: 0.7 }]}
              onPress={onSubmit}
              disabled={busy}
              activeOpacity={0.85}
            >
              {busy ? (
                <ActivityIndicator color={colors.parchment} />
              ) : (
                <Text style={styles.primaryBtnText}>Create Account</Text>
              )}
            </TouchableOpacity>

            <View style={styles.footer}>
              <Text style={styles.footerText}>Already a Titan?</Text>
              <Link href="/(auth)/login" asChild>
                <TouchableOpacity testID="goto-login-link">
                  <Text style={styles.footerLink}> Sign in</Text>
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
  scroll: { padding: spacing.lg, paddingTop: spacing.xl, flexGrow: 1 },
  logoWrap: { alignItems: "center", marginBottom: spacing.sm },
  brand: { textAlign: "center", fontFamily: fonts.displayBlack, fontSize: 28, color: colors.ink },
  tagline: {
    textAlign: "center",
    fontFamily: fonts.displayItalic,
    fontSize: 14,
    color: colors.goldDeep,
    marginTop: 4,
    marginBottom: spacing.lg,
  },
  card: {
    backgroundColor: colors.pureWhite,
    borderRadius: radius.xl,
    padding: spacing.xl,
    borderWidth: 1,
    borderColor: colors.birch,
    ...shadow.md,
  },
  title: { fontFamily: fonts.display, fontSize: 22, color: colors.ink },
  subtitle: { fontFamily: fonts.body, fontSize: 13, color: colors.ink4, marginTop: 4, marginBottom: spacing.md },
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
