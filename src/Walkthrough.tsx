import {Composition} from 'remotion';
import {WalkthroughVideo} from './WalkthroughVideo';

export const Walkthrough: React.FC = () => {
  return (
    <>
      <Composition
        id="PromoVideo"
        component={WalkthroughVideo}
        durationInFrames={300} // 10 seconds total (30fps)
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
