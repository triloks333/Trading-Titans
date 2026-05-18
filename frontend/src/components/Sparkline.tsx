import React, { useMemo } from "react";
import Svg, { Path, Defs, LinearGradient, Stop } from "react-native-svg";
import { colors } from "@/src/theme";

interface Props {
  points: number[];
  width?: number;
  height?: number;
  color?: string;
  fill?: boolean;
  strokeWidth?: number;
}

export default function Sparkline({ points, width = 80, height = 28, color, fill = false, strokeWidth = 1.5 }: Props) {
  const { d, area, stroke } = useMemo(() => {
    if (!points || points.length < 2) return { d: "", area: "", stroke: color || colors.ink4 };
    const min = Math.min(...points);
    const max = Math.max(...points);
    const range = max - min || 1;
    const stepX = width / (points.length - 1);
    const yFor = (v: number) => height - ((v - min) / range) * height;
    let pathD = `M0,${yFor(points[0])}`;
    for (let i = 1; i < points.length; i++) {
      pathD += ` L${(i * stepX).toFixed(2)},${yFor(points[i]).toFixed(2)}`;
    }
    const areaD = `${pathD} L${width},${height} L0,${height} Z`;
    const trend = points[points.length - 1] - points[0];
    const strokeColor = color || (trend >= 0 ? colors.bull : colors.bear);
    return { d: pathD, area: areaD, stroke: strokeColor };
  }, [points, width, height, color]);

  if (!d) return null;
  const gradId = `spark-${stroke.replace("#", "")}`;
  return (
    <Svg width={width} height={height}>
      {fill && (
        <Defs>
          <LinearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor={stroke} stopOpacity="0.3" />
            <Stop offset="1" stopColor={stroke} stopOpacity="0" />
          </LinearGradient>
        </Defs>
      )}
      {fill && <Path d={area} fill={`url(#${gradId})`} />}
      <Path d={d} stroke={stroke} strokeWidth={strokeWidth} fill="none" />
    </Svg>
  );
}
