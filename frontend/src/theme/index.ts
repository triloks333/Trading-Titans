// Trading Titans theme - Parchment + Imperial Gold
export const colors = {
  // Surfaces
  parchment: "#F5F2EC",
  warmWhite: "#FDFAF4",
  pureWhite: "#FFFFFF",
  cream: "#F9F6EE",
  sand: "#F0EDE4",
  birch: "#E4DDD0",
  // Brand
  goldDeep: "#8B6914",
  imperialGold: "#C9970C",
  goldMid: "#D4AF37",
  goldLight: "#E8C84A",
  goldPale: "#FFF8DC",
  goldBorder: "#C9A227",
  // Ink
  ink: "#1A1208",
  ink2: "#2D2210",
  ink3: "#5C4A28",
  ink4: "#8B7A5A",
  ink5: "#B8A88A",
  // Semantic
  bull: "#0A6B3F",
  bullLight: "#D1F4E5",
  bear: "#B91C1C",
  bearLight: "#FEE2E2",
  blue: "#1D4ED8",
  blueLight: "#DBEAFE",
  violet: "#6D28D9",
  violetLight: "#EDE9FE",
};

export const fonts = {
  display: "PlayfairDisplay_700Bold",
  displayBlack: "PlayfairDisplay_900Black",
  displayItalic: "PlayfairDisplay_700Bold_Italic",
  body: "DMSans_400Regular",
  bodyMed: "DMSans_500Medium",
  bodyBold: "DMSans_700Bold",
  mono: "DMMono_400Regular",
  monoMed: "DMMono_500Medium",
};

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
  xxxl: 48,
};

export const radius = {
  tag: 4,
  sm: 8,
  md: 10,
  lg: 12,
  xl: 16,
  pill: 100,
};

export const shadow = {
  sm: {
    shadowColor: "#1A1208",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  md: {
    shadowColor: "#1A1208",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 4,
    elevation: 3,
  },
  lg: {
    shadowColor: "#1A1208",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 5,
  },
  gold: {
    shadowColor: "#C9970C",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.25,
    shadowRadius: 8,
    elevation: 5,
  },
};

export const formatINR = (n: number, decimals = 2): string => {
  if (n === null || n === undefined || isNaN(n)) return "₹0";
  const abs = Math.abs(n);
  const sign = n < 0 ? "-" : "";
  const fixed = abs.toFixed(decimals);
  const [whole, dec] = fixed.split(".");
  // Indian numbering: last 3 digits, then 2-2 groups
  let result = "";
  if (whole.length > 3) {
    const last3 = whole.slice(-3);
    const rest = whole.slice(0, -3);
    const groups: string[] = [];
    for (let i = rest.length; i > 0; i -= 2) {
      groups.unshift(rest.slice(Math.max(0, i - 2), i));
    }
    result = groups.join(",") + "," + last3;
  } else {
    result = whole;
  }
  return `${sign}₹${result}${dec ? "." + dec : ""}`;
};

export const formatPct = (n: number): string => {
  if (n === null || n === undefined || isNaN(n)) return "0.00%";
  const sign = n >= 0 ? "+" : "";
  return `${sign}${n.toFixed(2)}%`;
};
