import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../screens/main/subscribe_screen.dart';
import '../screens/main/trade_screen.dart';
import '../screens/main/portfolio_screen.dart';
import '../screens/main/wallet_screen.dart';
import '../screens/main/glossary_screen.dart';
import '../screens/main/orders_screen.dart';
import '../screens/main/whatif_screen.dart';
import '../screens/main/autopsy_screen.dart';
import '../screens/main/analytics_screen.dart';
import '../screens/main/compete_screen.dart';

/// Metadata for an in-app page taggable via the admin '/' slash command.
class ChatRouteMeta {
  final String slashCommand;
  final String title;
  final String subtitle;
  final IconData icon;
  final String buttonLabel;
  final Color accentColor;
  final void Function(BuildContext context) onOpen;

  const ChatRouteMeta({
    required this.slashCommand,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.buttonLabel,
    required this.accentColor,
    required this.onOpen,
  });

  /// All supported slash command destinations in the app.
  static final List<ChatRouteMeta> registry = [
    ChatRouteMeta(
      slashCommand: '/top-up',
      title: 'Top-Up Demo Capital',
      subtitle: 'Instant virtual cash packs starting ₹199',
      icon: Icons.bolt_rounded,
      buttonLabel: 'Open Top-Up',
      accentColor: AppColors.goldDeep,
      onOpen: (context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SubscribeScreen(initialTabIndex: 1)),
      ),
    ),
    ChatRouteMeta(
      slashCommand: '/mentorship',
      title: 'VIP Mentorship & Plans',
      subtitle: 'Live 1-on-1 sessions with founders (Wed & Sat)',
      icon: Icons.workspace_premium_rounded,
      buttonLabel: 'View VIP Pass',
      accentColor: AppColors.violet,
      onOpen: (context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SubscribeScreen(initialTabIndex: 0)),
      ),
    ),
    ChatRouteMeta(
      slashCommand: '/trade',
      title: 'Trade & Live Watchlist',
      subtitle: 'Live quotes, stocks, and options chain',
      icon: Icons.candlestick_chart_rounded,
      buttonLabel: 'Open Trade',
      accentColor: AppColors.bull,
      onOpen: (context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TradeScreen()),
      ),
    ),
    ChatRouteMeta(
      slashCommand: '/portfolio',
      title: 'Portfolio & Holdings',
      subtitle: 'Live holdings, F&O positions & day P&L',
      icon: Icons.pie_chart_outline_rounded,
      buttonLabel: 'View Portfolio',
      accentColor: const Color(0xFF2563EB),
      onOpen: (context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PortfolioScreen()),
      ),
    ),
    ChatRouteMeta(
      slashCommand: '/wallet',
      title: 'Virtual Cash Wallet',
      subtitle: 'Demo balance, earnings & full ledger',
      icon: Icons.account_balance_wallet_rounded,
      buttonLabel: 'Open Wallet',
      accentColor: AppColors.imperialGold,
      onOpen: (context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WalletScreen()),
      ),
    ),
    ChatRouteMeta(
      slashCommand: '/glossary',
      title: 'Trading Glossary & Quiz',
      subtitle: 'Master Options, Greeks & market terms',
      icon: Icons.menu_book_rounded,
      buttonLabel: 'Open Glossary',
      accentColor: const Color(0xFF0D9488),
      onOpen: (context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const GlossaryScreen()),
      ),
    ),
    ChatRouteMeta(
      slashCommand: '/orders',
      title: 'Order History',
      subtitle: 'Executed, pending & cancelled orders',
      icon: Icons.receipt_long_rounded,
      buttonLabel: 'View Orders',
      accentColor: AppColors.ink3,
      onOpen: (context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OrdersScreen()),
      ),
    ),
    ChatRouteMeta(
      slashCommand: '/whatif',
      title: 'What-If Simulator',
      subtitle: 'Simulate trades before market execution',
      icon: Icons.lightbulb_outline_rounded,
      buttonLabel: 'Open What-If',
      accentColor: const Color(0xFFD97706),
      onOpen: (context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WhatIfScreen()),
      ),
    ),
    ChatRouteMeta(
      slashCommand: '/autopsy',
      title: 'Trade Autopsy',
      subtitle: 'Post-trade risk and execution analysis',
      icon: Icons.medical_services_outlined,
      buttonLabel: 'Open Autopsy',
      accentColor: AppColors.bear,
      onOpen: (context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AutopsyScreen()),
      ),
    ),
    ChatRouteMeta(
      slashCommand: '/analytics',
      title: 'Portfolio Analytics',
      subtitle: 'Win rate, Sharpe ratio & trade stats',
      icon: Icons.bar_chart_rounded,
      buttonLabel: 'View Analytics',
      accentColor: const Color(0xFF4F46E5),
      onOpen: (context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
      ),
    ),
    ChatRouteMeta(
      slashCommand: '/compete',
      title: 'Leaderboard & Challenges',
      subtitle: 'Community rankings & weekly rewards',
      icon: Icons.emoji_events_outlined,
      buttonLabel: 'View Leaderboard',
      accentColor: AppColors.goldDeep,
      onOpen: (context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CompeteScreen()),
      ),
    ),
  ];

  /// Resolves metadata from an explicit actionRoute or by scanning text for a slash command.
  static ChatRouteMeta? find(String? explicitRoute, [String? body]) {
    if (explicitRoute != null && explicitRoute.trim().isNotEmpty) {
      final clean = explicitRoute.trim().toLowerCase();
      for (final item in registry) {
        if (clean == item.slashCommand || clean == item.slashCommand.replaceAll('-', '')) {
          return item;
        }
      }
    }
    if (body != null && body.isNotEmpty) {
      final lower = body.toLowerCase();
      for (final item in registry) {
        if (lower.contains(item.slashCommand) ||
            (item.slashCommand == '/top-up' && lower.contains('/topup'))) {
          return item;
        }
      }
    }
    return null;
  }
}

/// A WhatsApp-style interactive attachment button card embedded in a message bubble.
class ChatRouteAttachmentCard extends StatelessWidget {
  final ChatRouteMeta meta;
  final bool isMine;

  const ChatRouteAttachmentCard({
    super.key,
    required this.meta,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 2),
      decoration: BoxDecoration(
        color: isMine ? Colors.white.withValues(alpha: 0.95) : AppColors.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: meta.accentColor.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: meta.accentColor.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: meta.accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(meta.icon, size: 18, color: meta.accentColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.title,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      meta.subtitle,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 10,
                        color: AppColors.ink4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                meta.onOpen(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: meta.accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                visualDensity: VisualDensity.compact,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    meta.buttonLabel,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 13, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
