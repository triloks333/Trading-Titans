import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import 'admin_analytics_screen.dart';
import 'admin_blog_screen.dart';
import 'admin_reward_screen.dart';
import 'wishlist_moderation_screen.dart';

/// Every admin tool behind one header: Broadcast, Rewards, Blog and Users.
/// Each tab hosts the existing tool, so no admin logic lives here.
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  static const _tabs = ['Broadcast', 'Rewards', 'Blog', 'Users'];
  late int _tab = widget.initialTab.clamp(0, _tabs.length - 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Admin panel', style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: AppCard.badge(AppColors.titanGoldSoft),
                    child: Text('ADMIN ONLY', style: AppText.badge.copyWith(color: AppColors.titanGold)),
                  ),
                ]),
              ),
              ListenableBuilder(
                listenable: ThemeService(),
                builder: (_, _) => AuthIconButton(
                  icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  label: 'Toggle light or dark theme',
                  onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
                ),
              ),
            ]),
          ),
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
            child: Row(children: [
              for (final (i, label) in _tabs.indexed)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: _tab == i,
                    label: label,
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => setState(() => _tab = i),
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: _tab == i ? AppColors.titanGold : Colors.transparent, width: 2)),
                        ),
                        child: Text(label, style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: _tab == i ? AppColors.ink : AppColors.ink3)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          // IndexedStack keeps each tool's half-filled form when switching tabs.
          Expanded(
            child: IndexedStack(index: _tab, children: [
              const AdminRewardScreen(only: 1),
              const AdminRewardScreen(only: 0),
              const AdminBlogScreen(embedded: true),
              Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                  child: Material(
                    color: AppColors.pureWhite,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WishlistModerationScreen())),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Expanded(child: Text('Wishlist moderation', style: AppText.bodyBold)),
                          Icon(Icons.chevron_right_rounded, color: AppColors.ink4),
                        ]),
                      ),
                    ),
                  ),
                ),
                const Expanded(child: AdminAnalyticsScreen(embedded: true)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
