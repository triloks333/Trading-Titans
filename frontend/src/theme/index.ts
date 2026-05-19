// Trading Titans theme - Light Blue (Zerodha/Groww-inspired)
export const colors = {
  // Surfaces (light blue-tinted)
  parchment: "#F4F7FB", // app background
  warmWhite: "#F8FAFD", // cards alt
  pureWhite: "#FFFFFF",
  cream: "#EEF4FB", // input bg / muted card
  sand: "#E6EEF7",
  birch: "#DDE7F2", // borders

  // Brand blues (primary)
  goldDeep: "#0B5FBF", // dark accent (replaces gold names internally, but used as primary)
  imperialGold: "#1A73E8", // primary action (kept name for backward-compat)
  goldMid: "#3B8BF2",
  goldLight: "#BBD7F8",
  goldPale: "#EAF2FC",
  goldBorder: "#A8C6EC",

  // Ink (cool blue-greys)
  ink: "#0B1B2B",
  ink2: "#102A43",
  ink3: "#334E68",
  ink4: "#627D98",
  ink5: "#9FB3C8",

  // Semantic
  bull: "#0F9D58",
  bullLight: "#D8F3E2",
  bear: "#D93025",
  bearLight: "#FCE4E2",
  blue: "#1A73E8",
  blueLight: "#DBEAFE",
  violet: "#6D28D9",
  violetLight: "#EDE9FE",
};

export const fonts = {
  // All Inter (Zerodha/Groww style)
  display: "Inter_700Bold",
  displayBlack: "Inter_900Black",
  displayItalic: "Inter_700Bold",
  body: "Inter_400Regular",
  bodyMed: "Inter_500Medium",
  bodyBold: "Inter_700Bold",
  mono: "Inter_500Medium", // Inter has tabular-nums; use medium for tabular numbers
  monoMed: "Inter_600SemiBold",
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
    shadowColor: "#0B1B2B",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  md: {
    shadowColor: "#0B1B2B",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 6,
    elevation: 3,
  },
  lg: {
    shadowColor: "#0B1B2B",
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.12,
    shadowRadius: 12,
    elevation: 6,
  },
  gold: {
    // primary-coloured shadow (now blue)
    shadowColor: "#1A73E8",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.22,
    shadowRadius: 10,
    elevation: 5,
  },
};

export const formatINR = (n: number, decimals = 2): string => {
  if (n === null || n === undefined || isNaN(n)) return "₹0";
  const abs = Math.abs(n);
  const sign = n < 0 ? "-" : "";
  const fixed = abs.toFixed(decimals);
  const [whole, dec] = fixed.split(".");
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
