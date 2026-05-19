import React from "react";
import { Stack, useRouter, useSegments } from "expo-router";
import { ActivityIndicator, View, StyleSheet, StatusBar } from "react-native";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import {
  useFonts,
  Inter_400Regular,
  Inter_500Medium,
  Inter_600SemiBold,
  Inter_700Bold,
  Inter_900Black,
} from "@expo-google-fonts/inter";
import { AuthProvider, useAuth } from "@/src/context/AuthContext";
import { colors } from "@/src/theme";

function Gate() {
  const { user, initializing } = useAuth();
  const segments = useSegments();
  const router = useRouter();

  React.useEffect(() => {
    if (initializing) return;
    const inAuth = segments[0] === "(auth)";
    const inTabs = segments[0] === "(tabs)";
    if (!user && !inAuth) {
      router.replace("/(auth)/login");
    } else if (user && (inAuth || segments.length === 0)) {
      router.replace("/(tabs)/dashboard");
    }
  }, [user, initializing, segments, router]);

  if (initializing) {
    return (
      <View style={styles.loader}>
        <ActivityIndicator size="large" color={colors.imperialGold} />
      </View>
    );
  }

  return (
    <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.parchment } }}>
      <Stack.Screen name="index" />
      <Stack.Screen name="(auth)" />
      <Stack.Screen name="(tabs)" />
      <Stack.Screen name="stock/[symbol]" options={{ presentation: "card" }} />
      <Stack.Screen name="whatif" />
      <Stack.Screen name="autopsy" />
      <Stack.Screen name="analytics" />
      <Stack.Screen name="orders" />
      <Stack.Screen name="subscribe" />
    </Stack>
  );
}

export default function RootLayout() {
  const [fontsLoaded] = useFonts({
    Inter_400Regular,
    Inter_500Medium,
    Inter_600SemiBold,
    Inter_700Bold,
    Inter_900Black,
  });

  if (!fontsLoaded) {
    return (
      <View style={styles.loader}>
        <ActivityIndicator size="large" color={colors.imperialGold} />
      </View>
    );
  }

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <StatusBar barStyle="dark-content" backgroundColor={colors.parchment} />
        <AuthProvider>
          <Gate />
        </AuthProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

const styles = StyleSheet.create({
  loader: { flex: 1, alignItems: "center", justifyContent: "center", backgroundColor: colors.parchment },
});
