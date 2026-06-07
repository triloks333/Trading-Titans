import { useState, useEffect } from 'react';
import { AnimatePresence } from 'motion/react';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { About } from './components/About';
import { Features } from './components/Features';
import { TopupPage } from './components/TopupPage';

function App() {
  const [currentPage, setCurrentPage] = useState<'home' | 'about' | 'features'>('home');
  const [isTopup, setIsTopup] = useState(false);

  useEffect(() => {
    const path = window.location.pathname;
    if (path === '/topup' || path === '/topup/') {
      setIsTopup(true);
    } else {
      setIsTopup(false);
    }
  }, []);

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
          <div className="mt-2 text-[10px] text-[#7888A3]">© {new Date().getFullYear()} Trading Titans. All rights reserved.</div>
        </div>
      </footer>
    </div>
  );
}

export default App;
