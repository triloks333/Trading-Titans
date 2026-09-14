import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';

/// Where a notification's button can send someone, as an admin picks it.
///
/// A fixed list rather than a free-text field: the value has to be one the app
/// knows how to open, and a typo would ship a button that silently does nothing on
/// every phone. Keys must exist in `kNotificationCtaRoutes` AND have a case in
/// `_openCta` — both live in notifications_screen.dart.
///
/// `''` is the no-button option. `_custom` swaps in a URL field instead, for
/// anywhere that only exists on the web.
const Map<String, String> kAdminCtaDestinations = {
  '': 'No button',
  'trade': 'Trade (buy / sell)',
  'portfolio': 'Portfolio',
  'orders': 'Order History',
  'wallet': 'Wallet',
  'league': 'League',
  'feature': 'Request a Feature',
  'wishlist': 'Community Wishlist',
  'referral': 'Refer & Earn',
  'plans': 'Plans & top-ups (paywall)',
  'chat': 'Titans Room (chat)',
  'blog': 'Blog',
  '_custom': 'A web link…',
};

class AdminRewardScreen extends StatefulWidget {
  const AdminRewardScreen({super.key});

  @override
  State<AdminRewardScreen> createState() => _AdminRewardScreenState();
}

class _AdminRewardScreenState extends State<AdminRewardScreen> {
  final _rewardFormKey = GlobalKey<FormState>();
  final _notifyFormKey = GlobalKey<FormState>();

  // Reward controllers
  final _rewardEmailController = TextEditingController();
  final _rewardAmountController = TextEditingController();
  final _rewardMessageController = TextEditingController();

  // Notification controllers
  final _notifyEmailController = TextEditingController();
  final _notifyTitleController = TextEditingController();
  final _notifyBodyController = TextEditingController();

  bool _submittingReward = false;
  bool _submittingNotify = false;

  bool _sendToAll = false;
  XFile? _pickedImage;
  Uint8List? _pickedBytes;

  // Optional call-to-action button on the notification.
  final _ctaLabelController = TextEditingController();
  final _ctaUrlController = TextEditingController();
  String _ctaDestination = '';

  bool get _ctaIsCustomUrl => _ctaDestination == '_custom';
  bool get _ctaWanted => _ctaDestination.isNotEmpty;

  @override
  void dispose() {
    _rewardEmailController.dispose();
    _rewardAmountController.dispose();
    _rewardMessageController.dispose();
    _notifyEmailController.dispose();
    _notifyTitleController.dispose();
    _notifyBodyController.dispose();
    _ctaLabelController.dispose();
    _ctaUrlController.dispose();
    super.dispose();
  }

  Future<void> _submitReward() async {
    if (!_rewardFormKey.currentState!.validate()) return;

    setState(() => _submittingReward = true);
    final email = _rewardEmailController.text.trim();
    final amount = double.tryParse(_rewardAmountController.text.trim()) ?? 0.0;
    final message = _rewardMessageController.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await SupabaseService().sendReward(
        email: email,
        amount: amount,
        message: message,
      );
      if (mounted) {
        _rewardEmailController.clear();
        _rewardAmountController.clear();
        _rewardMessageController.clear();
        messenger.showSnackBar(
          const SnackBar(content: Text('Reward sent successfully!')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _submittingReward = false);
      }
    }
  }

  Future<void> _submitNotification() async {
    if (!_notifyFormKey.currentState!.validate()) return;

    setState(() => _submittingNotify = true);
    final email = _notifyEmailController.text.trim();
    final title = _notifyTitleController.text.trim();
    final body = _notifyBodyController.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    try {
      String? imageUrl;
      if (_pickedImage != null && _pickedBytes != null) {
        imageUrl = await SupabaseService().uploadTicketAttachment(_pickedImage!.path, _pickedBytes!);
      }

      // Only one of route/url is ever sent. `_custom` means the destination is a
      // web link, so there is no in-app route to name.
      final ctaLabel = _ctaWanted ? _ctaLabelController.text.trim() : null;
      final ctaRoute = _ctaWanted && !_ctaIsCustomUrl ? _ctaDestination : null;
      final ctaUrl = _ctaIsCustomUrl ? _ctaUrlController.text.trim() : null;

      if (_sendToAll) {
        await SupabaseService().sendBroadcastNotification(
          title: title,
          body: body,
          imageUrl: imageUrl,
          ctaLabel: ctaLabel,
          ctaRoute: ctaRoute,
          ctaUrl: ctaUrl,
        );
      } else {
        await SupabaseService().sendCustomNotification(
          email: email,
          title: title,
          body: body,
          imageUrl: imageUrl,
          ctaLabel: ctaLabel,
          ctaRoute: ctaRoute,
          ctaUrl: ctaUrl,
        );
      }

      if (mounted) {
        _notifyEmailController.clear();
        _notifyTitleController.clear();
        _notifyBodyController.clear();
        _ctaLabelController.clear();
        _ctaUrlController.clear();
        setState(() {
          _pickedImage = null;
          _pickedBytes = null;
          _ctaDestination = '';
        });
        messenger.showSnackBar(
          SnackBar(content: Text('Notification sent to ${_sendToAll ? "all users" : email} successfully!')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _submittingNotify = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Admin Panel',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink),
          ),
          backgroundColor: AppColors.parchment,
          centerTitle: false,
          bottom: TabBar(
            labelColor: AppColors.imperialGold,
            unselectedLabelColor: AppColors.ink4,
            indicatorColor: AppColors.imperialGold,
            tabs: const [
              Tab(text: 'Give Reward'),
              Tab(text: 'Send Notification'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              // Tab 1: Reward Form
              SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Form(
                  key: _rewardFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Distribute Admin Rewards',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Reward a user with dummy cash and show a celebration popup in their app.',
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink4),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text('User Email Address', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _rewardEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'user@example.com',
                          hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                          border:       OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.imperialGold)),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter email';
                          if (!v.contains('@')) return 'Please enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text('Reward Amount (Demo Cash)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _rewardAmountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          hintText: 'e.g. 5000',
                          hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                          prefixText: '₹ ',
                          border:       OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.imperialGold)),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter amount';
                          final num = double.tryParse(v.trim());
                          if (num == null || num <= 0) return 'Please enter a valid positive number';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text('Celebration Message', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _rewardMessageController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'e.g. Thanks for reporting the critical bug! Keep up the good work.',
                          hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                          border:       OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.imperialGold)),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter a message';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submittingReward ? null : _submitReward,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.imperialGold,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _submittingReward
                              ?       SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: AppColors.pureWhite, strokeWidth: 2),
                                )
                              : Text('Send Reward', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.pureWhite)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Tab 2: Send Custom Notification
              SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Form(
                  key: _notifyFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send Notification',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Send a direct custom alert or notification to a user, or broadcast to everyone.',
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink4),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      
                      // Broadcast Checkbox Row
                      Row(
                        children: [
                          Checkbox(
                            value: _sendToAll,
                            activeColor: AppColors.imperialGold,
                            onChanged: (val) {
                              setState(() {
                                _sendToAll = val ?? false;
                              });
                            },
                          ),
                          Text(
                            'Send to All Users (Broadcast)',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),

                      if (!_sendToAll) ...[
                        Text('User Email Address', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _notifyEmailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'user@example.com',
                            hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                            border:       OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.imperialGold)),
                          ),
                          validator: (v) {
                            if (_sendToAll) return null;
                            if (v == null || v.trim().isEmpty) return 'Please enter email';
                            if (!v.contains('@')) return 'Please enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      Text('Notification Title', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _notifyTitleController,
                        decoration: InputDecoration(
                          hintText: 'e.g. Critical System Update',
                          hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                          border:       OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.imperialGold)),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter title';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),

                      Text('Notification Body', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _notifyBodyController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'e.g. Our servers are undergoing maintenance tonight...',
                          hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                          border:       OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.imperialGold)),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter body message';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Image Selector Option
                      Text('Attach an Image (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
                      const SizedBox(height: 6),
                      if (_pickedBytes != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          height: 120,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.birch),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            image: DecorationImage(
                              image: MemoryImage(_pickedBytes!),
                              fit: BoxFit.cover,
                            ),
                          ),
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _pickedImage = null;
                                _pickedBytes = null;
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
                              setState(() {
                                _pickedImage = image;
                                _pickedBytes = bytes;
                              });
                            }
                          },
                          icon: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.goldDeep),
                          label: Text('Select Image', style: GoogleFonts.inter(color: AppColors.ink, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            side:       BorderSide(color: AppColors.birch),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                          ),
                        ),

                      const SizedBox(height: AppSpacing.lg),

                      // ── Optional button on the notification ──────────────
                      Text('Add a Button (Optional)',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.ink2)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _ctaDestination,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderSide: BorderSide(color: AppColors.birch)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        items: kAdminCtaDestinations.entries
                            .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value,
                                      style: GoogleFonts.inter(
                                          fontSize: 14, color: AppColors.ink)),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _ctaDestination = v ?? ''),
                      ),
                      if (_ctaWanted) ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _ctaLabelController,
                          style: GoogleFonts.inter(color: AppColors.ink),
                          decoration: InputDecoration(
                            hintText: 'Button text, e.g. Request a feature',
                            hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                            border: OutlineInputBorder(
                                borderSide: BorderSide(color: AppColors.birch)),
                          ),
                          validator: (v) {
                            if (!_ctaWanted) return null;
                            if (v == null || v.trim().isEmpty) {
                              return 'Give the button some text, or pick "No button"';
                            }
                            return null;
                          },
                        ),
                        if (_ctaIsCustomUrl) ...[
                          const SizedBox(height: AppSpacing.sm),
                          TextFormField(
                            controller: _ctaUrlController,
                            style: GoogleFonts.inter(color: AppColors.ink),
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              hintText: 'https://…',
                              hintStyle:
                                  GoogleFonts.inter(color: AppColors.ink5),
                              border: OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.birch)),
                            ),
                            // https only, matching the check the app applies before
                            // launching. Rejected here as well so the mistake is
                            // caught while it can still be corrected, rather than
                            // shipping a button that does nothing.
                            validator: (v) {
                              if (!_ctaIsCustomUrl) return null;
                              final s = (v ?? '').trim();
                              if (!s.startsWith('https://')) {
                                return 'Must start with https://';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          'Older app versions show the notification without the '
                          'button, so mention the destination in the message too.',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: AppColors.ink4),
                        ),
                      ],

                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submittingNotify ? null : _submitNotification,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.imperialGold,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _submittingNotify
                              ?       SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: AppColors.pureWhite, strokeWidth: 2),
                                )
                              : Text(_sendToAll ? 'Broadcast Notification' : 'Send Notification', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.pureWhite)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
