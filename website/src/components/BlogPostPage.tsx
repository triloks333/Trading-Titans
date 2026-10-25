import React, { useEffect, useState } from 'react';
import { Navbar } from './Navbar';
import { SiteFooter } from './SiteFooter';
import { supabase } from '../lib/supabaseClient';
import { ArrowLeft, Calendar, Tag, Share2, Check, ExternalLink } from 'lucide-react';

interface BlogPost {
  slug: string;
  title: string;
  excerpt: string | null;
  body_markdown: string;
  cover_url: string | null;
  published_at: string;
  updated_at: string | null;
}

function parseMarkdownToBlocks(markdown: string) {
  const lines = (markdown || '').replace(/\r\n/g, '\n').split('\n');
  const blocks: { type: 'h2' | 'h3' | 'p' | 'ul' | 'code'; text?: string; items?: string[] }[] = [];
  let currentParagraph: string[] = [];
  let currentList: string[] = [];
  let inCode = false;
  let codeBuffer: string[] = [];

  const flushParagraph = () => {
    if (currentParagraph.length > 0) {
      blocks.push({ type: 'p', text: currentParagraph.join(' ') });
      currentParagraph = [];
    }
  };

  const flushList = () => {
    if (currentList.length > 0) {
      blocks.push({ type: 'ul', items: [...currentList] });
      currentList = [];
    }
  };

  for (const raw of lines) {
    const line = raw.trimEnd();

    if (line.trim().startsWith('```')) {
      flushParagraph();
      flushList();
      if (inCode) {
        blocks.push({ type: 'code', text: codeBuffer.join('\n') });
        codeBuffer = [];
        inCode = false;
      } else {
        inCode = true;
      }
      continue;
    }

    if (inCode) {
      codeBuffer.push(raw);
      continue;
    }

    if (line.trim() === '') {
      flushParagraph();
      flushList();
      continue;
    }

    if (line.startsWith('## ')) {
      flushParagraph();
      flushList();
      blocks.push({ type: 'h2', text: line.replace(/^##\s+/, '') });
      continue;
    }

    if (line.startsWith('### ')) {
      flushParagraph();
      flushList();
      blocks.push({ type: 'h3', text: line.replace(/^###\s+/, '') });
      continue;
    }

    if (line.startsWith('# ')) {
      flushParagraph();
      flushList();
      blocks.push({ type: 'h2', text: line.replace(/^#\s+/, '') });
      continue;
    }

    const bulletMatch = line.match(/^[-*]\s+(.*)$/);
    if (bulletMatch) {
      flushParagraph();
      currentList.push(bulletMatch[1]);
      continue;
    }

    const numberMatch = line.match(/^\d+\.\s+(.*)$/);
    if (numberMatch) {
      flushParagraph();
      currentList.push(numberMatch[1]);
      continue;
    }

    currentParagraph.push(line.trim());
  }

  flushParagraph();
  flushList();
  if (inCode && codeBuffer.length > 0) {
    blocks.push({ type: 'code', text: codeBuffer.join('\n') });
  }

  return blocks;
}

function renderFormattedText(text: string) {
  // Simple bold and inline code parser
  const parts = text.split(/(\*\*[^*]+\*\*|`[^`]+`)/g);
  return parts.map((part, index) => {
    if (part.startsWith('**') && part.endsWith('**')) {
      return <strong key={index} className="text-white font-semibold">{part.slice(2, -2)}</strong>;
    }
    if (part.startsWith('`') && part.endsWith('`')) {
      return (
        <code key={index} className="px-1.5 py-0.5 rounded bg-zinc-800 text-orange-400 font-mono text-xs">
          {part.slice(1, -1)}
        </code>
      );
    }
    return part;
  });
}

export const BlogPostPage: React.FC<{ slug?: string }> = ({ slug: propSlug }) => {
  const [post, setPost] = useState<BlogPost | null>(null);
  const [loading, setLoading] = useState(true);
  const [copied, setCopied] = useState(false);

  const slug = propSlug || window.location.pathname.replace(/^\/blog\/?/, '').replace(/\/$/, '');

  useEffect(() => {
    async function fetchPost() {
      if (!slug) {
        setLoading(false);
        return;
      }
      try {
        const { data, error } = await supabase
          .from('blog_posts')
          .select('slug, title, excerpt, body_markdown, cover_url, published_at, updated_at')
          .eq('slug', slug)
          .maybeSingle();

        if (error) {
          console.error('Error fetching blog post:', error);
        } else {
          setPost(data);
        }
      } catch (err) {
        console.error('Exception fetching post:', err);
      } finally {
        setLoading(false);
      }
    }
    fetchPost();
  }, [slug]);

  const handleCopyLink = () => {
    navigator.clipboard.writeText(window.location.href);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const getMarketBadge = (excerpt: string | null) => {
    if (!excerpt) return null;
    const match = excerpt.match(/^\[market:([^\]]+)\]/i);
    if (!match) return null;
    const map: Record<string, { label: string; color: string }> = {
      indian_stock: { label: 'Indian Stock Market', color: 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30' },
      crypto: { label: 'Cryptocurrency', color: 'bg-amber-500/20 text-amber-400 border-amber-500/30' },
      us_stock: { label: 'US Equities', color: 'bg-blue-500/20 text-blue-400 border-blue-500/30' },
      pakistan_stock: { label: 'Pakistan PSX', color: 'bg-teal-500/20 text-teal-400 border-teal-500/30' },
      italy_stock: { label: 'Borsa Italiana', color: 'bg-purple-500/20 text-purple-400 border-purple-500/30' },
    };
    return map[match[1].toLowerCase()] || { label: match[1].toUpperCase(), color: 'bg-zinc-800 text-zinc-300 border-zinc-700' };
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-black text-white flex flex-col justify-between">
        <Navbar />
        <div className="flex-1 flex items-center justify-center pt-24 pb-16">
          <div className="flex flex-col items-center gap-4">
            <div className="w-10 h-10 border-2 border-orange-500 border-t-transparent rounded-full animate-spin" />
            <p className="text-zinc-400 text-sm">Loading market analysis...</p>
          </div>
        </div>
        <SiteFooter />
      </div>
    );
  }

  if (!post) {
    return (
      <div className="min-h-screen bg-black text-white flex flex-col justify-between">
        <Navbar />
        <main className="flex-1 flex flex-col items-center justify-center text-center px-6 pt-32 pb-24">
          <h1 className="text-3xl font-bold mb-3">Article Not Found</h1>
          <p className="text-zinc-400 mb-8 max-w-md">
            The market analysis you are looking for may have been updated or moved.
          </p>
          <a
            href="/blog"
            className="inline-flex items-center gap-2 px-6 py-3 rounded-xl bg-orange-600 hover:bg-orange-500 text-white font-medium transition-colors"
          >
            <ArrowLeft className="w-4 h-4" /> Browse All Articles
          </a>
        </main>
        <SiteFooter />
      </div>
    );
  }

  const badge = getMarketBadge(post.excerpt);
  const cleanExcerpt = (post.excerpt || '').replace(/^\[market:[^\]]+\]\s*/i, '');
  const blocks = parseMarkdownToBlocks(post.body_markdown);
  const formattedDate = post.published_at
    ? new Date(post.published_at).toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      })
    : '';

  return (
    <div className="min-h-screen bg-black text-white selection:bg-[#e8702a] selection:text-white" style={{ fontFamily: "'Inter', sans-serif" }}>
      <Navbar />

      <main className="pt-28 pb-20 px-4 md:px-8 max-w-4xl mx-auto">
        {/* Breadcrumb & Navigation */}
        <div className="flex items-center justify-between gap-4 mb-8">
          <a
            href="/blog"
            className="inline-flex items-center gap-2 text-sm text-zinc-400 hover:text-white transition-colors"
          >
            <ArrowLeft className="w-4 h-4" /> Back to Intel &amp; News
          </a>
          <button
            onClick={handleCopyLink}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-zinc-800 bg-zinc-900/80 hover:bg-zinc-800 text-xs text-zinc-300 transition-colors"
          >
            {copied ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Share2 className="w-3.5 h-3.5 text-zinc-400" />}
            {copied ? 'Copied' : 'Share Article'}
          </button>
        </div>

        {/* Header Meta */}
        <div className="space-y-4 mb-8">
          <div className="flex flex-wrap items-center gap-2">
            {badge && (
              <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold border ${badge.color}`}>
                <Tag className="w-3 h-3" />
                {badge.label}
              </span>
            )}
            {formattedDate && (
              <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-zinc-900 border border-zinc-800 text-zinc-400">
                <Calendar className="w-3 h-3" />
                {formattedDate}
              </span>
            )}
          </div>

          <h1 className="text-3xl md:text-5xl font-extrabold tracking-tight leading-tight text-white">
            {post.title}
          </h1>

          {cleanExcerpt && (
            <p className="text-lg md:text-xl text-zinc-300 leading-relaxed font-normal border-l-2 border-orange-500 pl-4 py-1">
              {cleanExcerpt}
            </p>
          )}
        </div>

        {/* Hero Cover Image */}
        {post.cover_url && (
          <div className="relative rounded-2xl overflow-hidden border border-zinc-800 mb-10 shadow-2xl bg-zinc-900">
            <img
              src={post.cover_url}
              alt={post.title}
              className="w-full h-auto max-h-[460px] object-cover"
              loading="eager"
            />
          </div>
        )}

        {/* Article Body */}
        <article className="space-y-6 text-zinc-300 leading-relaxed text-base md:text-lg">
          {blocks.map((block, idx) => {
            if (block.type === 'h2') {
              return (
                <h2 key={idx} className="text-2xl md:text-3xl font-bold text-white pt-6 pb-2 border-b border-zinc-800/80">
                  {block.text}
                </h2>
              );
            }
            if (block.type === 'h3') {
              return (
                <h3 key={idx} className="text-xl md:text-2xl font-semibold text-white pt-4 pb-1">
                  {block.text}
                </h3>
              );
            }
            if (block.type === 'ul' && block.items) {
              return (
                <ul key={idx} className="space-y-2.5 my-4 pl-5 list-disc marker:text-orange-500">
                  {block.items.map((item, i) => (
                    <li key={i} className="text-zinc-300 leading-relaxed">
                      {renderFormattedText(item)}
                    </li>
                  ))}
                </ul>
              );
            }
            if (block.type === 'code') {
              return (
                <pre key={idx} className="p-4 rounded-xl bg-zinc-900 border border-zinc-800 overflow-x-auto text-sm font-mono text-zinc-200">
                  <code>{block.text}</code>
                </pre>
              );
            }
            return (
              <p key={idx} className="leading-relaxed text-zinc-300">
                {block.text ? renderFormattedText(block.text) : null}
              </p>
            );
          })}
        </article>

        {/* Call to Action Box */}
        <div className="mt-16 p-8 rounded-2xl bg-gradient-to-br from-zinc-900 via-zinc-900 to-orange-950/30 border border-orange-500/30 shadow-2xl relative overflow-hidden">
          <div className="relative z-10 flex flex-col md:flex-row items-center justify-between gap-6">
            <div className="space-y-2 text-center md:text-left">
              <span className="text-xs font-bold uppercase tracking-wider text-orange-400">Trading Titans App</span>
              <h3 className="text-2xl font-bold text-white">Trade this setup with zero risk</h3>
              <p className="text-sm text-zinc-400 max-w-md">
                Practise trading equities, options &amp; crypto with real-time live prices. Get ₹1,100 demo starting capital on signup.
              </p>
            </div>
            <a
              href="https://play.google.com/store/apps/details?id=com.tradingtitans.app"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 px-6 py-3.5 rounded-xl bg-gradient-to-r from-orange-600 to-amber-600 hover:from-orange-500 hover:to-amber-500 text-white font-bold text-sm shadow-lg shadow-orange-900/30 transition-all shrink-0"
            >
              Download App Free
              <ExternalLink className="w-4 h-4" />
            </a>
          </div>
        </div>
      </main>

      <SiteFooter />
    </div>
  );
};
