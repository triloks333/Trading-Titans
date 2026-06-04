import React from 'react';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';

function App() {
  return (
    <div className="min-h-screen bg-[#EDEEF5] selection:bg-[#9fff00] selection:text-black font-sans">
      <Navbar />
      <main>
        <Hero />
      </main>
    </div>
  );
}

export default App;
