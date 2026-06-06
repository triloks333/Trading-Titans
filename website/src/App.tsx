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
    </div>
  );
}

export default App;
