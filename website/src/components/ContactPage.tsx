import React, { useState } from 'react';
import { Navbar } from './Navbar';
import { SiteFooter } from './SiteFooter';
import { Mail, Clock, ShieldAlert, CheckCircle2 } from 'lucide-react';

export const ContactPage: React.FC = () => {
  const [submitted, setSubmitted] = useState(false);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [message, setMessage] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name || !email || !message) return;
    setSubmitted(true);
  };

  return (
    <div className="min-h-screen bg-black text-white selection:bg-[#e8702a] selection:text-white" style={{ fontFamily: "'Inter', sans-serif" }}>
      <Navbar />

      <main className="pt-32 pb-24 px-6 md:px-12 max-w-5xl mx-auto">
        {/* Header */}
        <div className="text-center max-w-3xl mx-auto mb-16">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-white/20 bg-white/5 text-xs text-white/80 font-medium mb-4">
            <Mail className="w-3.5 h-3.5 text-[#e8702a]" />
            Official Support &amp; Grievance
          </div>
          <h1 className="text-4xl md:text-5xl font-extrabold tracking-tight mb-4">
            Contact <span className="font-playfair italic text-white">Us</span>
          </h1>
          <p className="text-lg text-white/70 leading-relaxed">
            Have questions, feedback, or need assistance with your account? The Trading Titans team is here to help.
          </p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-12 gap-10">
          {/* Contact Details Column */}
          <div className="lg:col-span-5 space-y-6">
            <div className="bg-zinc-900/80 border border-white/15 rounded-2xl p-6 md:p-8 backdrop-blur-sm">
              <h2 className="text-xl font-bold text-white mb-6">Get in Touch</h2>

              <div className="space-y-6 text-sm">
                <div className="flex items-start gap-4">
                  <div className="w-10 h-10 rounded-xl bg-white/10 flex items-center justify-center shrink-0 border border-white/15 text-[#e8702a]">
                    <Mail className="w-5 h-5" />
                  </div>
                  <div>
                    <span className="block text-xs uppercase tracking-wider text-white/50 font-semibold mb-0.5">Primary Support Email</span>
                    <a href="mailto:support@thetradingtitans.com" className="text-base font-bold text-white hover:text-[#e8702a] transition-colors">
                      support@thetradingtitans.com
                    </a>
                    <p className="text-xs text-white/50 mt-1">For general inquiries, account assistance, and technical bug reports.</p>
                  </div>
                </div>

                <div className="flex items-start gap-4">
                  <div className="w-10 h-10 rounded-xl bg-white/10 flex items-center justify-center shrink-0 border border-white/15 text-[#e8702a]">
                    <Clock className="w-5 h-5" />
                  </div>
                  <div>
                    <span className="block text-xs uppercase tracking-wider text-white/50 font-semibold mb-0.5">Operating Hours &amp; Response Time</span>
                    <p className="text-sm font-medium text-white">Monday – Friday: 9:00 AM – 6:00 PM IST</p>
                    <p className="text-xs text-white/50 mt-1">We typically respond to all customer tickets within 24 to 48 business hours.</p>
                  </div>
                </div>

                <div className="flex items-start gap-4">
                  <div className="w-10 h-10 rounded-xl bg-white/10 flex items-center justify-center shrink-0 border border-white/15 text-[#e8702a]">
                    <ShieldAlert className="w-5 h-5" />
                  </div>
                  <div>
                    <span className="block text-xs uppercase tracking-wider text-white/50 font-semibold mb-0.5">Operated By</span>
                    <p className="text-sm font-semibold text-white">KashivWealth Management LLP</p>
                    <p className="text-xs text-white/50 mt-1">Registered Entity in India under the Limited Liability Partnership Act.</p>
                  </div>
                </div>
              </div>
            </div>

            <div className="bg-white/5 border border-white/10 rounded-2xl p-6 text-xs text-white/60 leading-relaxed">
              <strong className="text-white block mb-1">Educational Simulator Notice:</strong>
              Trading Titans is strictly an educational paper trading simulation platform. We do not provide financial advisory, stock broker services, or execute real money trades.
            </div>
          </div>

          {/* Contact Form Column */}
          <div className="lg:col-span-7">
            <div className="bg-zinc-900/80 border border-white/15 rounded-2xl p-6 md:p-8 backdrop-blur-sm">
              <h2 className="text-xl font-bold text-white mb-2">Send us a Message</h2>
              <p className="text-sm text-white/60 mb-6">Fill in the form below and our support team will get back to you directly.</p>

              {submitted ? (
                <div className="py-12 text-center">
                  <CheckCircle2 className="w-16 h-16 text-emerald-400 mx-auto mb-4" />
                  <h3 className="text-xl font-bold text-white mb-2">Message Received!</h3>
                  <p className="text-sm text-white/70 max-w-md mx-auto">
                    Thank you for reaching out. We have received your inquiry and our support team will reply to <span className="text-white font-medium">{email}</span> shortly.
                  </p>
                </div>
              ) : (
                <form onSubmit={handleSubmit} className="space-y-4">
                  <div>
                    <label className="block text-xs font-semibold uppercase tracking-wider text-white/60 mb-1.5">
                      Your Name
                    </label>
                    <input
                      type="text"
                      required
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                      placeholder="e.g. John Doe"
                      className="w-full bg-white/5 border border-white/15 rounded-xl px-4 py-3 text-sm text-white placeholder-white/30 focus:outline-none focus:border-[#e8702a] transition-colors"
                    />
                  </div>

                  <div>
                    <label className="block text-xs font-semibold uppercase tracking-wider text-white/60 mb-1.5">
                      Your Email Address
                    </label>
                    <input
                      type="email"
                      required
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      placeholder="e.g. user@example.com"
                      className="w-full bg-white/5 border border-white/15 rounded-xl px-4 py-3 text-sm text-white placeholder-white/30 focus:outline-none focus:border-[#e8702a] transition-colors"
                    />
                  </div>

                  <div>
                    <label className="block text-xs font-semibold uppercase tracking-wider text-white/60 mb-1.5">
                      Message / Inquiry
                    </label>
                    <textarea
                      required
                      rows={5}
                      value={message}
                      onChange={(e) => setMessage(e.target.value)}
                      placeholder="Please describe how we can assist you..."
                      className="w-full bg-white/5 border border-white/15 rounded-xl px-4 py-3 text-sm text-white placeholder-white/30 focus:outline-none focus:border-[#e8702a] transition-colors resize-none"
                    />
                  </div>

                  <button
                    type="submit"
                    className="w-full bg-white text-zinc-950 font-bold text-sm py-3.5 rounded-xl hover:bg-zinc-200 transition-colors shadow-lg cursor-pointer"
                  >
                    Send Message to Support
                  </button>
                </form>
              )}
            </div>
          </div>
        </div>
      </main>

      <SiteFooter />
    </div>
  );
};
