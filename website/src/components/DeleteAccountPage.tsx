import React from 'react';

export const DeleteAccountPage: React.FC = () => {
  return (
    <div className="min-h-screen bg-[#EDEEF5] flex flex-col justify-center items-center px-4 font-sans selection:bg-[#9fff00] selection:text-black">
      <div className="max-w-md w-full bg-white border border-[#D0D4DF] rounded-2xl p-8 text-center shadow-lg">
        
        {/* Trash/Deletion Icon */}
        <div className="mx-auto w-16 h-16 bg-[#FFF5F5] rounded-full flex items-center justify-center text-red-500 text-3xl font-bold mb-6">
          🗑️
        </div>

        <h1 className="text-2xl font-extrabold text-[#0f172a] tracking-tight mb-3">
          Delete Your Account & Data
        </h1>
        
        <p className="text-[#525E75] text-sm leading-relaxed mb-6">
          If you wish to permanently delete your Trading Titans account, virtual trading progress, and all associated personal data from our databases, please request deletion below.
        </p>

        <div className="bg-[#FFF5F5] border border-red-200 text-red-800 rounded-xl p-4 text-xs font-semibold mb-6 leading-relaxed">
          ⚠️ Warning: Account deletion is permanent. All virtual cash balances (including top-ups), portfolio progress, and transaction histories will be completely purged and cannot be recovered.
        </div>

        <a
          href="mailto:support@thetradingtitans.com?subject=Request%20Account%20Deletion&body=Hello%20Trading%20Titans%20Support%2C%0A%0AI%20would%20like%20to%20request%20the%20permanent%20deletion%20of%20my%20account%20and%20all%20associated%20data.%0A%0AEmail%20Address%3A%20%5BEnter%20your%20account%20email%5D%0AUsername%20%2F%20User%20ID%3A%20%5BEnter%20your%20username%20if%20known%5D"
          className="w-full block bg-red-600 hover:bg-red-700 text-white text-center font-semibold py-3.5 px-6 rounded-xl shadow-md transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-red-600/50"
        >
          Request Deletion via Email
        </a>

        <div className="mt-8 pt-6 border-t border-[#EDEEF5] text-xs text-zinc-400">
          We will process all deletion requests within 48 hours.
        </div>
      </div>
    </div>
  );
};
