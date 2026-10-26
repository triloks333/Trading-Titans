import { useEffect, useState } from 'react';
import { STARTING_CASH } from '../lib/config';

export function ConfirmPage() {
  const [browserInfo, setBrowserInfo] = useState({ isMobile: false, isAndroid: false });

  useEffect(() => {
    const ua = navigator.userAgent.toLowerCase();
    const isAndroid = ua.includes('android');
    const isIOS = ua.includes('iphone') || ua.includes('ipad') || ua.includes('ipod');
    setBrowserInfo({
      isMobile: isAndroid || isIOS,
      isAndroid,
    });
  }, []);

  const handleOpenApp = () => {
    // Try to open the app using the custom scheme
    window.location.href = 'tradingtitans://callback';
    
    // Fallback if the app isn't installed
    setTimeout(() => {
      if (browserInfo.isAndroid) {
        // Redirect to Play Store search or direct app URL if known in future
        alert('If the app did not open automatically, please ensure you have the Trading Titans app installed from the Google Play Store.');
      } else {
        alert('If the app did not open automatically, please open the Trading Titans app manually.');
      }
    }, 2000);
  };

  return (
    <div className="min-h-screen bg-[#EDEEF5] flex flex-col justify-center items-center px-4 font-sans selection:bg-[#9fff00] selection:text-black">
      <div className="max-w-md w-full bg-white border border-[#D0D4DF] rounded-2xl p-8 text-center shadow-lg transition-transform duration-300 hover:scale-[1.01]">
        
        {/* Animated Checkmark Circle */}
        <div className="mx-auto w-16 h-16 bg-[#D8E6FF] rounded-full flex items-center justify-center text-[#2563eb] text-3xl font-bold animate-bounce mb-6">
          ✓
        </div>

        <h1 className="text-2xl font-extrabold text-[#0f172a] tracking-tight mb-3">
          Email Verified Successfully!
        </h1>
        
        <p className="text-[#525E75] text-sm leading-relaxed mb-8">
          Thank you for confirming your email. Your Trading Titans account is now fully active, and your {STARTING_CASH} virtual cash is ready to trade.
        </p>

        {browserInfo.isMobile ? (
          <button
            onClick={handleOpenApp}
            className="w-full bg-[#2563eb] hover:bg-[#1d4ed8] text-white font-semibold py-3.5 px-6 rounded-xl shadow-md transition-all duration-200 hover:shadow-lg focus:outline-none focus:ring-2 focus:ring-[#2563eb]/50"
          >
            Open Trading Titans App
          </button>
        ) : (
          <div className="bg-[#F1F3F9] border border-[#E2E4EC] rounded-xl p-4 text-xs text-[#525E75] font-medium">
            📱 Please open the <strong>Trading Titans</strong> app on your mobile device to sign in and start trading.
          </div>
        )}

        <div className="mt-8 pt-6 border-t border-[#EDEEF5]">
          <p className="text-[10px] text-[#7888A3] leading-normal uppercase tracking-wider font-semibold">
            Trading Titans Arena
          </p>
        </div>
      </div>
    </div>
  );
}
