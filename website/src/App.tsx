import { useState } from 'react';
import { AnimatePresence } from 'motion/react';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { About } from './components/About';
import { Features } from './components/Features';
import { Analytics } from '@vercel/analytics/react';

function App() {
  const [currentPage, setCurrentPage] = useState<'home' | 'about' | 'features'>('home');

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
      <Analytics />
    </div>
  );
}

export default App;
