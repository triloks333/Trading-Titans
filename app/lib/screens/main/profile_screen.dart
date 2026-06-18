import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/crown_logo.dart';
import 'subscribe_screen.dart';
import 'orders_screen.dart';
import 'analytics_screen.dart';
import 'autopsy_screen.dart';
import 'whatif_screen.dart';
import 'watchlist_screen.dart';
import 'notifications_screen.dart';
import 'refer_earn_screen.dart';
import 'support_tickets_screen.dart';
import 'admin_reward_screen.dart';
import 'community_wishlist_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    final themeService = context.watch<ThemeService>();
    
    String themeName = 'Light Mode';
    if (themeService.themeMode == ThemeMode.dark) themeName = 'Dark Mode';
    if (themeService.themeMode == ThemeMode.system) themeName = 'System Default';

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: AppCard.primary,
              child: Column(
                children: [
                  const CrownLogo(size: 56, withRing: true),
                  const SizedBox(height: AppSpacing.md),
                  Text(user?.name ?? 'Titan', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(user?.email ?? 'you@domain.com', style: GoogleFonts.inter(fontSize: 14, color: AppColors.ink4)),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                    decoration: AppCard.badge(user?.subscriptionActive == true ? AppColors.bullLight : AppColors.cream),
                    child: Text(
                      user?.subscriptionActive == true ? 'ACTIVE' : 'FREE STARTER',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: user?.subscriptionActive == true ? AppColors.bull : AppColors.ink4, letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _detailRow('Wallet Balance', '₹${user?.walletBalance.toStringAsFixed(0) ?? '0'}'),
                  const SizedBox(height: AppSpacing.sm),
                  _detailRow('P&L', '₹${user?.totalRealizedPnl.toStringAsFixed(0) ?? '0'}',
                      valueColor: (user?.totalRealizedPnl ?? 0) >= 0 ? AppColors.bull : AppColors.bear),
                  const SizedBox(height: AppSpacing.sm),
                  _detailRow('Member Since', user != null ? user.createdAt.toLocal().toShortDateString() : '-'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: () async {
                final authService = context.read<AuthService>();
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscribeScreen()));
                await authService.refreshUser();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.imperialGold,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: Text('Top up Demo Cash', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.pureWhite, letterSpacing: 0.5)),
            ),
            const SizedBox(height: AppSpacing.lg),
            
            
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'ACCOUNT ACTIONS',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.ink4, letterSpacing: 0.8),
              ),
            ),
            _menuItem(context, Icons.star, 'Watchlist', const WatchlistScreen()),
            _menuItem(context, Icons.bar_chart, 'Analytics', const AnalyticsScreen()),
            _menuItem(context, Icons.receipt_long, 'Order History', const OrdersScreen()),
            _menuItem(context, Icons.notifications_outlined, 'Notifications', const NotificationsScreen()),
            _menuItem(context, Icons.card_giftcard, 'Refer & Earn', const ReferEarnScreen()),
            _menuItem(context, Icons.lightbulb_outline, 'What-If Simulator', const WhatIfScreen()),
            _menuItem(context, Icons.medical_services_outlined, 'Autopsy', const AutopsyScreen()),
            
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'SETTINGS & SUPPORT',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.ink4, letterSpacing: 0.8),
              ),
            ),
            _menuItemAction(context, Icons.privacy_tip_outlined, 'Privacy Policy', () => _showPrivacyPolicy(context)),
            _menuItemAction(context, Icons.gavel_outlined, 'Terms & Conditions', () => _showTerms(context)),
            _menuItemAction(context, Icons.rocket_launch_outlined, 'Request a Feature', () => _showRequestFeature(context)),
            _menuItem(context, Icons.forum_outlined, 'Community Wishlist', const CommunityWishlistScreen()),
            _menuItemAction(context, Icons.bug_report_outlined, 'Report an Issue', () => _showReportIssue(context)),
            _menuItemActionWithSubtitle(context, Icons.palette_outlined, 'App Theme', themeName, () => _showThemeSelector(context)),
            if (user?.isAdmin == true) ...[
              _menuItem(context, Icons.rate_review_outlined, 'Submitted Tickets', const SupportTicketsScreen()),
              _menuItem(context, Icons.admin_panel_settings_outlined, 'Admin Panel', const AdminRewardScreen()),
            ],

            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: () async {
                await auth.logout();
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppColors.bear),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: Text('Sign Out', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.bear, letterSpacing: 0.5)),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Center(child: Text('Trading Titans v1.1', style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink5))),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(BuildContext context, IconData icon, String label, Widget screen) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: OutlinedButton(
        onPressed: () async {
          final authService = context.read<AuthService>();
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
          await authService.refreshUser();
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: AppSpacing.lg),
          side:       BorderSide(color: AppColors.birch),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          backgroundColor: AppColors.pureWhite,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.ink2),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: GoogleFonts.inter(color: AppColors.ink, fontWeight: FontWeight.w500))),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.ink4),
          ],
        ),
      ),
    );
  }

  Widget _menuItemAction(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: AppSpacing.lg),
          side:       BorderSide(color: AppColors.birch),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          backgroundColor: AppColors.pureWhite,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.ink2),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: GoogleFonts.inter(color: AppColors.ink, fontWeight: FontWeight.w500))),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.ink4),
          ],
        ),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Privacy Policy', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    Text(
                      'At Trading Titans, we respect your privacy. This policy outlines how we handle your data:\n\n'
                      '1. Data Collection: We collect account email, profile name, and virtual transaction logs to facilitate virtual trading simulations.\n\n'
                      '2. Security: Your password credentials are securely handled via Supabase Auth services.\n\n'
                      '3. Market Feeds: We query public and premium quote APIs. No financial information is shared with third parties.\n\n'
                      '4. Changes: We reserve the right to modify this policy at any time.',
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink3, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTerms(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Terms & Conditions', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    Text(
                      'Welcome to Trading Titans. By accessing our app, you agree to these Terms and Conditions:\n\n'
                      '1. Virtual Trading Only: All trades, cash, balances, and P&L displayed in this application are strictly virtual. No real-world money is risked or invested.\n\n'
                      '2. Content Accuracy: Market quote data is sourced from third-party APIs and may experience delays. We are not liable for trading simulations based on delayed data.\n\n'
                      '3. System Integrity: Any exploitation of bugs, virtual cash balances, or API feeds will result in immediate termination of the user account.',
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink3, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRequestFeature(BuildContext context) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    XFile? pickedImage;
    Uint8List? pickedBytes;
    bool submitting = false;
    List<Map<String, dynamic>> similarFeatures = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: AppSpacing.lg,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Request a Feature', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
                const SizedBox(height: AppSpacing.xs),
                Text('Tell us what we should build next!', style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink4)),
                const SizedBox(height: AppSpacing.md),
                
                Text('Feature Title', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                const SizedBox(height: 6),
                TextField(
                  controller: titleController,
                  onChanged: (val) async {
                    if (val.trim().length >= 5) {
                      final results = await SupabaseService().searchSimilarFeatures(val.trim());
                      setModalState(() {
                        similarFeatures = results;
                      });
                    } else {
                      setModalState(() {
                        similarFeatures = [];
                      });
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Enter feature name...',
                    hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                    border:       OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.imperialGold)),
                  ),
                ),
                if (similarFeatures.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.goldPale,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.goldBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Similar requests found. Upvote instead?',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink),
                        ),
                        const SizedBox(height: 6),
                        ...similarFeatures.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '- ${f['title']}',
                                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const CommunityWishlistScreen()),
                                  );
                                },
                                child: Text(
                                  'View & Upvote',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.imperialGold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                
                Text('Description', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                const SizedBox(height: 6),
                TextField(
                  controller: descController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Describe the feature in detail...',
                    hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                    border:       OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.imperialGold)),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                
                Text('Attach an Image (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                const SizedBox(height: 6),
                if (pickedBytes != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.birch),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      image: DecorationImage(
                        image: MemoryImage(pickedBytes!),
                        fit: BoxFit.cover,
                      ),
                    ),
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () {
                        setModalState(() {
                          pickedImage = null;
                          pickedBytes = null;
                        });
                      },
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final image = await picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        final bytes = await image.readAsBytes();
                        setModalState(() {
                          pickedImage = image;
                          pickedBytes = bytes;
                        });
                      }
                    },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text('Select Image', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      side:       BorderSide(color: AppColors.birch),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                  ),
                
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            final title = titleController.text.trim();
                            final desc = descController.text.trim();
                            if (title.isEmpty || desc.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please fill in both title and description.')),
                              );
                              return;
                            }
                            if (title.length < 5 || desc.length < 10) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Title must be at least 5 chars, Description at least 10 chars.')),
                              );
                              return;
                            }
                            
                            setModalState(() => submitting = true);
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              String? imageUrl;
                              if (pickedImage != null && pickedBytes != null) {
                                imageUrl = await SupabaseService().uploadTicketAttachment(pickedImage!.path, pickedBytes!);
                              }
                              await SupabaseService().submitFeatureRequest(
                                title: title,
                                description: desc,
                                imageUrl: imageUrl,
                              );
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Thank you! Your feature request has been submitted to the wishlist.')),
                                );
                              }
                            } catch (e) {
                              setModalState(() => submitting = false);
                              messenger.showSnackBar(
                                SnackBar(content: Text('Error: ${e.toString().replaceAll("Exception:", "")}')),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.imperialGold,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: submitting
                        ?       SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: AppColors.pureWhite, strokeWidth: 2),
                          )
                        : Text('Submit', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.pureWhite)),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showReportIssue(BuildContext context) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    XFile? pickedImage;
    Uint8List? pickedBytes;
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: AppSpacing.lg,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Report an Issue', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
                const SizedBox(height: AppSpacing.xs),
                Text('Encountered a bug? Let us know so we can fix it.', style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink4)),
                const SizedBox(height: AppSpacing.md),
                
                Text('Issue Title', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                const SizedBox(height: 6),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    hintText: 'Enter issue name...',
                    hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                    border:       OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.imperialGold)),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                
                Text('Description', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                const SizedBox(height: 6),
                TextField(
                  controller: descController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Describe the bug or issue...',
                    hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                    border:       OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.imperialGold)),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                
                Text('Attach an Image (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                const SizedBox(height: 6),
                if (pickedBytes != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.birch),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      image: DecorationImage(
                        image: MemoryImage(pickedBytes!),
                        fit: BoxFit.cover,
                      ),
                    ),
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () {
                        setModalState(() {
                          pickedImage = null;
                          pickedBytes = null;
                        });
                      },
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final image = await picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        final bytes = await image.readAsBytes();
                        setModalState(() {
                          pickedImage = image;
                          pickedBytes = bytes;
                        });
                      }
                    },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text('Select Image', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      side:       BorderSide(color: AppColors.birch),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                  ),
                
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            final title = titleController.text.trim();
                            final desc = descController.text.trim();
                            if (title.isEmpty || desc.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please fill in both title and description.')),
                              );
                              return;
                            }
                            
                            setModalState(() => submitting = true);
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              String? imageUrl;
                              if (pickedImage != null && pickedBytes != null) {
                                imageUrl = await SupabaseService().uploadTicketAttachment(pickedImage!.path, pickedBytes!);
                              }
                              await SupabaseService().submitSupportTicket(
                                type: 'issue',
                                title: title,
                                content: desc,
                                imageUrl: imageUrl,
                              );
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Thank you! Our engineering team will review the issue.')),
                                );
                              }
                            } catch (e) {
                              setModalState(() => submitting = false);
                              messenger.showSnackBar(
                                SnackBar(content: Text('Error submitting report: $e')),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.imperialGold,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: submitting
                        ?       SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: AppColors.pureWhite, strokeWidth: 2),
                          )
                        : Text('Submit Report', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.pureWhite)),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showThemeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) {
        final themeService = context.watch<ThemeService>();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.birch,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Choose Theme',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _themeOption(
                  context,
                  icon: Icons.light_mode_outlined,
                  title: 'Light Mode',
                  isSelected: themeService.themeMode == ThemeMode.light,
                  onTap: () {
                    themeService.setThemeMode(ThemeMode.light);
                    Navigator.pop(context);
                  },
                ),
                _themeOption(
                  context,
                  icon: Icons.dark_mode_outlined,
                  title: 'Dark Mode',
                  isSelected: themeService.themeMode == ThemeMode.dark,
                  onTap: () {
                    themeService.setThemeMode(ThemeMode.dark);
                    Navigator.pop(context);
                  },
                ),
                _themeOption(
                  context,
                  icon: Icons.settings_brightness_outlined,
                  title: 'System Default',
                  isSelected: themeService.themeMode == ThemeMode.system,
                  onTap: () {
                    themeService.setThemeMode(ThemeMode.system);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _themeOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.goldPale : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isSelected ? AppColors.goldBorder : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? AppColors.imperialGold : AppColors.ink2,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    color: isSelected ? AppColors.imperialGold : AppColors.ink,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: AppColors.imperialGold,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItemActionWithSubtitle(
    BuildContext context,
    IconData icon,
    String label,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: AppSpacing.lg),
          side:       BorderSide(color: AppColors.birch),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          backgroundColor: AppColors.pureWhite,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.ink2),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.inter(color: AppColors.ink, fontWeight: FontWeight.w500, fontSize: 14)),
                  Text(subtitle, style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 12)),
                ],
              ),
            ),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.ink4),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 13)),
        Text(value, style: GoogleFonts.inter(color: valueColor ?? AppColors.ink, fontWeight: FontWeight.w700, fontSize: 14)),
      ],
    );
  }
}

extension on DateTime {
  String toShortDateString() {
    return '$day/${month.toString().padLeft(2, '0')}/${year.toString().substring(2)}';
  }
}
