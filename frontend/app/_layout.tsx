import React from "react";
import { Stack, useRouter, useSegments } from "expo-router";
import { ActivityIndicator, View, StyleSheet, StatusBar } from "react-native";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import {
  useFonts as usePlayfair,
  PlayfairDisplay_700Bold,
  PlayfairDisplay_900Black,
  PlayfairDisplay_700Bold_Italic,
} from "@expo-google-fonts/playfair-display";
import {
  useFonts as useDMSans,
  DMSans_400Regular,
  DMSans_500Medium,
  DMSans_700Bold,
} from "@expo-google-fonts/dm-sans";
import {
  useFonts as useDMMono,
  DMMono_400Regular,
  DMMono_500Medium,
} from "@expo-google-fonts/dm-mono";
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
  const [pf] = usePlayfair({ PlayfairDisplay_700Bold, PlayfairDisplay_900Black, PlayfairDisplay_700Bold_Italic });
  const [ds] = useDMSans({ DMSans_400Regular, DMSans_500Medium, DMSans_700Bold });
  const [dm] = useDMMono({ DMMono_400Regular, DMMono_500Medium });

  if (!pf || !ds || !dm) {
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
