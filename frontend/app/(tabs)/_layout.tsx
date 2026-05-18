import React from "react";
import { Tabs } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { colors, fonts } from "@/src/theme";

export default function TabsLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.imperialGold,
        tabBarInactiveTintColor: colors.ink4,
        tabBarStyle: {
          backgroundColor: colors.warmWhite,
          borderTopColor: colors.birch,
          borderTopWidth: 1,
          height: 64,
          paddingTop: 6,
          paddingBottom: 8,
        },
        tabBarLabelStyle: { fontFamily: fonts.bodyMed, fontSize: 11 },
      }}
    >
      <Tabs.Screen
        name="dashboard"
        options={{
          title: "Dashboard",
          tabBarIcon: ({ color, size }) => <Ionicons name="grid-outline" size={size - 2} color={color} />,
        }}
      />
      <Tabs.Screen
        name="trade"
        options={{
          title: "Trade",
          tabBarIcon: ({ color, size }) => <Ionicons name="trending-up" size={size - 2} color={color} />,
        }}
      />
      <Tabs.Screen
        name="compete"
        options={{
          title: "Compete",
          tabBarIcon: ({ color, size }) => <Ionicons name="trophy-outline" size={size - 2} color={color} />,
        }}
      />
      <Tabs.Screen
        name="wallet"
        options={{
          title: "Wallet",
          tabBarIcon: ({ color, size }) => <Ionicons name="wallet-outline" size={size - 2} color={color} />,
        }}
      />
      <Tabs.Screen
        name="profile"
        options={{
          title: "Profile",
          tabBarIcon: ({ color, size }) => <Ionicons name="person-outline" size={size - 2} color={color} />,
        }}
      />
    </Tabs>
  );
}
