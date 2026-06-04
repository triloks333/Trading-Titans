import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
  Img,
} from 'remotion';
import React from 'react';

// Setup screen frame references using generated authentic mockups
const slide1 = require('../public/playstore_landscape_flutter_08.jpg');
const slide2 = require('../public/playstore_landscape_flutter_04.jpg');

export const WalkthroughVideo: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  // Slide transition point at 150 frames (5 seconds)
  const slideProgress = spring({
    frame: frame - 150,
    fps,
    config: {damping: 15},
  });

  // Calculate slide placement offsets for smooth horizontal panning
  const slide1TranslateX = interpolate(slideProgress, [0, 1], [0, -1920]);
  const slide2TranslateX = interpolate(slideProgress, [0, 1], [1920, 0]);

  return (
    <AbsoluteFill style={{backgroundColor: '#0f0f12'}}>
      {/* Slide 1 Container */}
      <div
        style={{
          position: 'absolute',
          width: '100%',
          height: '100%',
          transform: `translateX(${slide1TranslateX}px)`,
        }}
      >
        <Img
          src={slide1}
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
          }}
        />
      </div>

      {/* Slide 2 Container */}
      <div
        style={{
          position: 'absolute',
          width: '100%',
          height: '100%',
          transform: `translateX(${slide2TranslateX}px)`,
        }}
      >
        <Img
          src={slide2}
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
          }}
        />
      </div>
    </AbsoluteFill>
  );
};
