import { useState, useEffect } from 'react';
import { Navbar } from './components/Navbar';
import { SpotlightHero } from './components/SpotlightHero';
import { ValueProps } from './components/ValueProps';
import { HowItWorks } from './components/HowItWorks';
import { Showcase } from './components/Showcase';
import { DownloadSection } from './components/DownloadSection';
import { SiteFooter } from './components/SiteFooter';
import { TopupPage } from './components/TopupPage';
import { ConfirmPage } from './components/ConfirmPage';
import { TermsPage } from './components/TermsPage';
import { PreregTermsPage } from './components/PreregTermsPage';
import { PrivacyPage } from './components/PrivacyPage';
import { RefundPage } from './components/RefundPage';
import { DeleteAccountPage } from './components/DeleteAccountPage';
import { AboutPage } from './components/AboutPage';
import { ContactPage } from './components/ContactPage';
import { BlogIndexPage } from './components/BlogIndexPage';
import { BlogPostPage } from './components/BlogPostPage';
import { PaperTradingIndiaPage } from './components/PaperTradingIndiaPage';
import { OptionsSimulatorPage } from './components/OptionsSimulatorPage';
import { BrokerageCalculatorPage } from './components/BrokerageCalculatorPage';
import { MobileStickyInstallBar } from './components/MobileStickyInstallBar';

type Route =
  | 'home'
  | 'topup'
  | 'confirm'
  | 'terms'
  | 'prereg-terms'
  | 'privacy'
  | 'refund'
  | 'delete-account'
  | 'about'
  | 'contact'
  | 'blog-index'
  | 'blog-post'
  | 'paper-trading'
  | 'options-simulator'
  | 'brokerage-calculator';

function resolveRoute(path: string): Route {
  const p = path.replace(/\/+$/, '') || '/';
  if (p === '/blog') return 'blog-index';
  if (p.startsWith('/blog/')) return 'blog-post';
  switch (p) {
    case '/paper-trading-app-india':
    case '/paper-trading-india':
    case '/paper-trading':
      return 'paper-trading';
    case '/options-trading-simulator':
    case '/options-simulator':
    case '/options-paper-trading':
      return 'options-simulator';
    case '/brokerage-calculator':
    case '/calculator':
    case '/fno-brokerage-calculator':
      return 'brokerage-calculator';
    case '/about':
    case '/about-us':
      return 'about';
    case '/contact':
    case '/contact-us':
      return 'contact';
    case '/topup':
    case '/pricing':
    case '/plans':
      return 'topup';
    case '/confirm':
      return 'confirm';
    case '/terms':
      return 'terms';
    case '/prereg-terms':
      return 'prereg-terms';
    case '/privacy':
      return 'privacy';
    case '/refund':
    case '/refund-policy':
    case '/refunds':
      return 'refund';
    case '/delete-account':
      return 'delete-account';
    default:
      return 'home';
  }
}

function App() {
  const [route, setRoute] = useState<Route>('home');

  useEffect(() => {
    setRoute(resolveRoute(window.location.pathname));
  }, []);

  const renderContent = () => {
    switch (route) {
      case 'paper-trading':
        return <PaperTradingIndiaPage />;
      case 'options-simulator':
        return <OptionsSimulatorPage />;
      case 'brokerage-calculator':
        return <BrokerageCalculatorPage />;
      case 'about':
        return <AboutPage />;
      case 'contact':
        return <ContactPage />;
      case 'confirm':
        return <ConfirmPage />;
      case 'topup':
        return <TopupPage />;
      case 'terms':
        return <TermsPage />;
      case 'prereg-terms':
        return <PreregTermsPage />;
      case 'privacy':
        return <PrivacyPage />;
      case 'refund':
        return <RefundPage />;
      case 'delete-account':
        return <DeleteAccountPage />;
      case 'blog-index':
        return <BlogIndexPage />;
      case 'blog-post':
        return <BlogPostPage />;
      default:
        return (
          <div className="min-h-screen bg-black tracking-[-0.02em] selection:bg-[#e8702a] selection:text-white" style={{ fontFamily: "'Inter', sans-serif" }}>
            <Navbar />
            <main>
              <SpotlightHero />
              <ValueProps />
              <HowItWorks />
              <Showcase />
              <DownloadSection />
            </main>
            <SiteFooter />
          </div>
        );
    }
  };

  return (
    <>
      {renderContent()}
      <MobileStickyInstallBar />
    </>
  );
}

export default App;
