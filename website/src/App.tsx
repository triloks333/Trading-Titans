import { useState, useEffect } from 'react';
import { AnimatePresence } from 'motion/react';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { About } from './components/About';
import { Features } from './components/Features';
import { TopupPage } from './components/TopupPage';
import { ConfirmPage } from './components/ConfirmPage';
import { TermsPage } from './components/TermsPage';
import { PreregTermsPage } from './components/PreregTermsPage';
import { PrivacyPage } from './components/PrivacyPage';
import { DeleteAccountPage } from './components/DeleteAccountPage';

function App() {
  const [currentPage, setCurrentPage] = useState<'home' | 'about' | 'features'>('home');
  const [isTopup, setIsTopup] = useState(false);
  const [isConfirm, setIsConfirm] = useState(false);
  const [isTerms, setIsTerms] = useState(false);
  const [isPreregTerms, setIsPreregTerms] = useState(false);
  const [isPrivacy, setIsPrivacy] = useState(false);
  const [isDelete, setIsDelete] = useState(false);

  useEffect(() => {
    const path = window.location.pathname;
    if (path === '/topup' || path === '/topup/') {
      setIsTopup(true);
    } else if (path === '/confirm' || path === '/confirm/') {
      setIsConfirm(true);
    } else if (path === '/prereg-terms' || path === '/prereg-terms/') {
      setIsPreregTerms(true);
    } else if (path === '/terms' || path === '/terms/') {
      setIsTerms(true);
    } else if (path === '/privacy' || path === '/privacy/') {
      setIsPrivacy(true);
    } else if (path === '/delete-account' || path === '/delete-account/') {
      setIsDelete(true);
    } else {
      setIsTopup(false);
      setIsConfirm(false);
      setIsTerms(false);
      setIsPreregTerms(false);
      setIsPrivacy(false);
      setIsDelete(false);
    }
  }, []);

  if (isConfirm) {
    return <ConfirmPage />;
  }

  if (isPreregTerms) {
    return <PreregTermsPage />;
  }

  if (isTerms) {
    return <TermsPage />;
  }

  if (isPrivacy) {
    return <PrivacyPage />;
  }

  if (isDelete) {
    return <DeleteAccountPage />;
  }

  if (isTopup) {
    return <TopupPage />;
  }

  return (
    <div className="min-h-screen bg-[#EDEEF5] selection:bg-[#9fff00] selection:text-black font-sans flex flex-col justify-between">
      <Navbar currentPage={currentPage} onPageChange={setCurrentPage} />
      <main className="flex-grow">
        <AnimatePresence mode="wait">
          {currentPage === 'home' && <Hero key="home" />}
          {currentPage === 'about' && <About key="about" />}
          {currentPage === 'features' && <Features key="features" />}
        </AnimatePresence>
      </main>
      <footer className="bg-[#E2E4EC] py-6 px-4 text-center border-t border-[#D0D4DF]">
        <div className="max-w-4xl mx-auto text-xs text-[#525E75] font-medium leading-relaxed">
          <strong>Trading Titans is a virtual paper-trading simulation game for educational purposes only. We do not provide real financial advice, real trading execution, or real payouts.</strong>
          <div className="mt-2 flex justify-center gap-4 text-[10px] text-[#7888A3]">
            <span>© {new Date().getFullYear()} Trading Titans. All rights reserved.</span>
            <a href="/terms" className="hover:underline font-semibold text-[#525E75]">Terms & Conditions</a>
            <a href="/prereg-terms" className="hover:underline font-semibold text-[#525E75]">Pre-registration Terms</a>
            <a href="/privacy" className="hover:underline font-semibold text-[#525E75]">Privacy Policy</a>
          </div>
        </div>
      </footer>
    </div>
  );
}

export default App;
