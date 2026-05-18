import React, { useMemo } from "react";
import { View, Text, StyleSheet, Dimensions } from "react-native";
import Svg, { Path, Defs, LinearGradient, Stop, Circle, Line } from "react-native-svg";
import { colors, fonts } from "@/src/theme";

interface Props {
  points: { t: number; v: number }[];
  height?: number;
}

export default function PriceChart({ points, height = 200 }: Props) {
  const width = Dimensions.get("window").width - 32;
  const { d, area, stroke, min, max, first, last } = useMemo(() => {
    if (!points || points.length < 2) {
      return { d: "", area: "", stroke: colors.ink4, min: 0, max: 0, first: 0, last: 0 };
    }
    const values = points.map((p) => p.v);
    const _min = Math.min(...values);
    const _max = Math.max(...values);
    const range = _max - _min || 1;
    const padY = 10;
    const usableH = height - padY * 2;
    const stepX = width / (points.length - 1);
    const yFor = (v: number) => padY + (usableH - ((v - _min) / range) * usableH);
    let pathD = `M0,${yFor(values[0]).toFixed(2)}`;
    for (let i = 1; i < values.length; i++) {
      pathD += ` L${(i * stepX).toFixed(2)},${yFor(values[i]).toFixed(2)}`;
    }
    const areaD = `${pathD} L${width.toFixed(2)},${height} L0,${height} Z`;
    const _first = values[0];
    const _last = values[values.length - 1];
    const strokeColor = _last >= _first ? colors.bull : colors.bear;
    return { d: pathD, area: areaD, stroke: strokeColor, min: _min, max: _max, first: _first, last: _last };
  }, [points, width, height]);

  if (!d) {
    return (
      <View style={[styles.empty, { height }]}>
        <Text style={styles.emptyText}>No chart data</Text>
      </View>
    );
  }

  return (
    <View style={styles.wrap}>
      <Svg width={width} height={height}>
        <Defs>
          <LinearGradient id="chartGrad" x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor={stroke} stopOpacity="0.25" />
            <Stop offset="1" stopColor={stroke} stopOpacity="0" />
          </LinearGradient>
        </Defs>
        {/* Grid lines */}
        <Line x1="0" y1={height * 0.25} x2={width} y2={height * 0.25} stroke={colors.birch} strokeWidth="0.5" strokeDasharray="3,3" />
        <Line x1="0" y1={height * 0.5} x2={width} y2={height * 0.5} stroke={colors.birch} strokeWidth="0.5" strokeDasharray="3,3" />
        <Line x1="0" y1={height * 0.75} x2={width} y2={height * 0.75} stroke={colors.birch} strokeWidth="0.5" strokeDasharray="3,3" />
        <Path d={area} fill="url(#chartGrad)" />
        <Path d={d} stroke={stroke} strokeWidth="2" fill="none" strokeLinejoin="round" />
        {/* End dot */}
        <Circle cx={width - 2} cy={(() => {
          const values = points.map((p) => p.v);
          const _min = Math.min(...values);
          const _max = Math.max(...values);
          const range = _max - _min || 1;
          const padY = 10;
          const usableH = height - padY * 2;
          return padY + (usableH - ((last - _min) / range) * usableH);
        })()} r="4" fill={stroke} stroke={colors.parchment} strokeWidth="2" />
      </Svg>
      <View style={styles.yLabels}>
        <Text style={styles.yLabel}>{max.toFixed(2)}</Text>
        <Text style={styles.yLabel}>{min.toFixed(2)}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { position: "relative" },
  empty: { alignItems: "center", justifyContent: "center" },
  emptyText: { fontFamily: fonts.body, color: colors.ink4 },
  yLabels: { position: "absolute", right: 4, top: 0, bottom: 0, justifyContent: "space-between" },
  yLabel: { fontFamily: fonts.mono, fontSize: 10, color: colors.ink4 },
});
