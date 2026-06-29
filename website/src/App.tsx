import { useState, useEffect } from 'react';
import { Navbar } from './components/Navbar';
import { SpotlightHero } from './components/SpotlightHero';
import { ValueProps } from './components/ValueProps';
import { HowItWorks } from './components/HowItWorks';
import { Showcase } from './components/Showcase';
import { PreRegSection } from './components/PreRegSection';
import { SiteFooter } from './components/SiteFooter';
import { TopupPage } from './components/TopupPage';
import { ConfirmPage } from './components/ConfirmPage';
import { TermsPage } from './components/TermsPage';
import { PreregTermsPage } from './components/PreregTermsPage';
import { PrivacyPage } from './components/PrivacyPage';
import { DeleteAccountPage } from './components/DeleteAccountPage';

type Route = 'home' | 'topup' | 'confirm' | 'terms' | 'prereg-terms' | 'privacy' | 'delete-account';

function resolveRoute(path: string): Route {
  const p = path.replace(/\/+$/, '') || '/';
  switch (p) {
    case '/topup': return 'topup';
    case '/confirm': return 'confirm';
    case '/terms': return 'terms';
    case '/prereg-terms': return 'prereg-terms';
    case '/privacy': return 'privacy';
    case '/delete-account': return 'delete-account';
    default: return 'home';
  }
}

function App() {
  const [route, setRoute] = useState<Route>('home');

  useEffect(() => {
    setRoute(resolveRoute(window.location.pathname));
  }, []);

  if (route === 'confirm') return <ConfirmPage />;
  if (route === 'topup') return <TopupPage />;
  if (route === 'terms') return <TermsPage />;
  if (route === 'prereg-terms') return <PreregTermsPage />;
  if (route === 'privacy') return <PrivacyPage />;
  if (route === 'delete-account') return <DeleteAccountPage />;

  return (
    <div className="min-h-screen bg-black tracking-[-0.02em] selection:bg-[#e8702a] selection:text-white" style={{ fontFamily: "'Inter', sans-serif" }}>
      <Navbar />
      <main>
        <SpotlightHero />
        <ValueProps />
        <HowItWorks />
        <Showcase />
        <PreRegSection />
      </main>
      <SiteFooter />
    </div>
  );
}

export default App;
