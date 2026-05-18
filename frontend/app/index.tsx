import React from "react";
import { View, ActivityIndicator, StyleSheet } from "react-native";
import { colors } from "@/src/theme";

export default function Index() {
  return (
    <View style={styles.c}>
      <ActivityIndicator size="large" color={colors.imperialGold} />
    </View>
  );
}

const styles = StyleSheet.create({
  c: { flex: 1, backgroundColor: colors.parchment, alignItems: "center", justifyContent: "center" },
});
