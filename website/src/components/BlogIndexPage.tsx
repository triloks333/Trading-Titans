import React, { useEffect, useState } from 'react';
import { Navbar } from './Navbar';
import { SiteFooter } from './SiteFooter';
import { supabase } from '../lib/supabaseClient';
import { ArrowRight, Calendar, Tag, Search, Sparkles } from 'lucide-react';

interface BlogPostSummary {
  slug: string;
  title: string;
  excerpt: string | null;
  cover_url: string | null;
  published_at: string;
}

const MARKET_TABS = [
  { id: 'all', label: 'All Markets' },
  { id: 'indian_stock', label: 'Indian Stocks' },
  { id: 'crypto', label: 'Crypto' },
  { id: 'us_stock', label: 'US Equities' },
  { id: 'pakistan_stock', label: 'Pakistan Stocks' },
  { id: 'italy_stock', label: 'Italy Stocks' },
];

export const BlogIndexPage: React.FC = () => {
  const [posts, setPosts] = useState<BlogPostSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');

  useEffect(() => {
    async function fetchPosts() {
      try {
        const { data, error } = await supabase
          .from('blog_posts')
          .select('slug, title, excerpt, cover_url, published_at')
          .order('published_at', { ascending: false })
          .limit(50);

        if (error) {
          console.error('Error fetching blog posts:', error);
        } else {
          setPosts(data || []);
        }
      } catch (err) {
        console.error('Exception fetching blogs:', err);
      } finally {
        setLoading(false);
      }
    }
    fetchPosts();
  }, []);

  const getMarket = (excerpt: string | null) => {
    if (!excerpt) return 'general';
    const match = excerpt.match(/^\[market:([^\]]+)\]/i);
    return match ? match[1].toLowerCase() : 'general';
  };

  const getMarketBadge = (market: string) => {
    const map: Record<string, { label: string; color: string }> = {
      indian_stock: { label: 'Indian Stocks', color: 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30' },
      crypto: { label: 'Crypto', color: 'bg-amber-500/20 text-amber-400 border-amber-500/30' },
      us_stock: { label: 'US Equities', color: 'bg-blue-500/20 text-blue-400 border-blue-500/30' },
      pakistan_stock: { label: 'Pakistan PSX', color: 'bg-teal-500/20 text-teal-400 border-teal-500/30' },
      italy_stock: { label: 'Italy Borsa', color: 'bg-purple-500/20 text-purple-400 border-purple-500/30' },
    };
    return map[market] || { label: market.toUpperCase(), color: 'bg-zinc-800 text-zinc-300 border-zinc-700' };
  };

  const filteredPosts = posts.filter((p) => {
    const m = getMarket(p.excerpt);
    const matchesTab = activeTab === 'all' || m === activeTab;
    const cleanExcerpt = (p.excerpt || '').replace(/^\[market:[^\]]+\]\s*/i, '').toLowerCase();
    const matchesSearch =
      searchQuery === '' ||
      p.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
      cleanExcerpt.includes(searchQuery.toLowerCase());
    return matchesTab && matchesSearch;
  });

  return (
    <div className="min-h-screen bg-black text-white selection:bg-[#e8702a] selection:text-white" style={{ fontFamily: "'Inter', sans-serif" }}>
      <Navbar />

      <main className="pt-32 pb-24 px-4 md:px-8 max-w-6xl mx-auto">
        {/* Header */}
        <div className="text-center max-w-3xl mx-auto mb-12">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-orange-500/30 bg-orange-500/10 text-xs text-orange-400 font-medium mb-4">
            <Sparkles className="w-3.5 h-3.5" />
            Live Market Intel &amp; Research
          </div>
          <h1 className="text-4xl md:text-5xl font-extrabold tracking-tight mb-4 text-white">
            Market Intelligence &amp; <span className="text-transparent bg-clip-text bg-gradient-to-r from-orange-400 to-amber-400">Analysis</span>
          </h1>
          <p className="text-base md:text-lg text-zinc-400 leading-relaxed">
            Deep dives, macroeconomic insights, and actionable market strategies across Indian equities, global stock markets, and digital assets.
          </p>
        </div>

        {/* Filters and Search Bar */}
        <div className="flex flex-col md:flex-row items-center justify-between gap-4 mb-10 pb-6 border-b border-zinc-800">
          {/* Tabs */}
          <div className="flex flex-wrap items-center gap-2 w-full md:w-auto">
            {MARKET_TABS.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                  activeTab === tab.id
                    ? 'bg-orange-600 text-white shadow-md shadow-orange-900/30'
                    : 'bg-zinc-900 text-zinc-400 hover:text-white hover:bg-zinc-800 border border-zinc-800'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          {/* Search */}
          <div className="relative w-full md:w-64">
            <Search className="w-4 h-4 text-zinc-500 absolute left-3 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search intel..."
              className="w-full pl-9 pr-3 py-2 rounded-lg bg-zinc-900 border border-zinc-800 text-xs text-white placeholder-zinc-500 focus:outline-none focus:border-orange-500 transition-colors"
            />
          </div>
        </div>

        {/* Loading State */}
        {loading ? (
          <div className="flex flex-col items-center justify-center py-20">
            <div className="w-10 h-10 border-2 border-orange-500 border-t-transparent rounded-full animate-spin mb-4" />
            <p className="text-zinc-500 text-sm">Loading market updates...</p>
          </div>
        ) : filteredPosts.length === 0 ? (
          <div className="text-center py-20 bg-zinc-900/40 rounded-2xl border border-zinc-800">
            <p className="text-zinc-400 font-medium">No articles found matching your criteria.</p>
          </div>
        ) : (
          /* Grid of Articles */
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {filteredPosts.map((post) => {
              const market = getMarket(post.excerpt);
              const badge = getMarketBadge(market);
              const cleanExcerpt = (post.excerpt || '').replace(/^\[market:[^\]]+\]\s*/i, '');
              const formattedDate = post.published_at
                ? new Date(post.published_at).toLocaleDateString('en-US', {
                    month: 'short',
                    day: 'numeric',
                    year: 'numeric',
                  })
                : '';

              return (
                <a
                  key={post.slug}
                  href={`/blog/${post.slug}`}
                  className="group flex flex-col rounded-2xl bg-zinc-900/70 border border-zinc-800/80 hover:border-orange-500/50 overflow-hidden shadow-lg hover:shadow-orange-950/20 transition-all duration-300"
                >
                  {/* Cover */}
                  {post.cover_url ? (
                    <div className="relative aspect-video w-full overflow-hidden bg-zinc-950">
                      <img
                        src={post.cover_url}
                        alt={post.title}
                        className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                        loading="lazy"
                      />
                    </div>
                  ) : (
                    <div className="aspect-video w-full bg-gradient-to-br from-zinc-800 to-zinc-900 flex items-center justify-center">
                      <Tag className="w-8 h-8 text-zinc-600" />
                    </div>
                  )}

                  {/* Content */}
                  <div className="flex-1 p-5 flex flex-col justify-between">
                    <div>
                      <div className="flex items-center gap-2 mb-3">
                        <span className={`px-2.5 py-0.5 rounded-full text-[11px] font-semibold border ${badge.color}`}>
                          {badge.label}
                        </span>
                        {formattedDate && (
                          <span className="text-[11px] text-zinc-500 flex items-center gap-1">
                            <Calendar className="w-3 h-3" />
                            {formattedDate}
                          </span>
                        )}
                      </div>

                      <h2 className="text-lg font-bold text-white group-hover:text-orange-400 transition-colors line-clamp-2 leading-snug mb-2">
                        {post.title}
                      </h2>

                      {cleanExcerpt && (
                        <p className="text-zinc-400 text-xs line-clamp-3 leading-relaxed mb-4">
                          {cleanExcerpt}
                        </p>
                      )}
                    </div>

                    <div className="inline-flex items-center gap-1.5 text-xs font-semibold text-orange-400 pt-2 border-t border-zinc-800/60 group-hover:translate-x-1 transition-transform">
                      Read Analysis <ArrowRight className="w-3.5 h-3.5" />
                    </div>
                  </div>
                </a>
              );
            })}
          </div>
        )}
      </main>

      <SiteFooter />
    </div>
  );
};
