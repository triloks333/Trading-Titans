import React from "react";
import Svg, { Path, Defs, LinearGradient, Stop, Circle } from "react-native-svg";

interface Props {
  size?: number;
  withRing?: boolean;
}

export default function CrownLogo({ size = 64, withRing = true }: Props) {
  return (
    <Svg width={size} height={size} viewBox="0 0 100 100">
      <Defs>
        <LinearGradient id="goldGrad" x1="0" y1="0" x2="1" y2="1">
          <Stop offset="0" stopColor="#E8C84A" />
          <Stop offset="0.5" stopColor="#C9970C" />
          <Stop offset="1" stopColor="#8B6914" />
        </LinearGradient>
      </Defs>
      {withRing && (
        <Circle cx="50" cy="50" r="46" fill="#F9F6EE" stroke="#C9A227" strokeWidth="2" />
      )}
      {/* Crown shape */}
      <Path
        d="M22 62 L28 38 L40 52 L50 30 L60 52 L72 38 L78 62 Z"
        fill="url(#goldGrad)"
        stroke="#8B6914"
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
      <Path d="M22 64 L78 64 L78 70 L22 70 Z" fill="#C9970C" stroke="#8B6914" strokeWidth="1.5" />
      {/* Gems */}
      <Circle cx="28" cy="38" r="3" fill="#FFF8DC" stroke="#8B6914" strokeWidth="1" />
      <Circle cx="50" cy="30" r="3.5" fill="#FFF8DC" stroke="#8B6914" strokeWidth="1" />
      <Circle cx="72" cy="38" r="3" fill="#FFF8DC" stroke="#8B6914" strokeWidth="1" />
    </Svg>
  );
}
