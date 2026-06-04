import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';

class AdminRewardScreen extends StatefulWidget {
  const AdminRewardScreen({super.key});

  @override
  State<AdminRewardScreen> createState() => _AdminRewardScreenState();
}

class _AdminRewardScreenState extends State<AdminRewardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _amountController = TextEditingController();
  final _messageController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _amountController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitReward() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final email = _emailController.text.trim();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final message = _messageController.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await SupabaseService().sendReward(
        email: email,
        amount: amount,
        message: message,
      );
      if (mounted) {
        _emailController.clear();
        _amountController.clear();
        _messageController.clear();
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
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Give Reward',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink),
        ),
        backgroundColor: AppColors.parchment,
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
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
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'user@example.com',
                    hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                    border: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
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
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'e.g. 5000',
                    hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                    prefixText: '₹ ',
                    border: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
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
                  controller: _messageController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'e.g. Thanks for reporting the critical bug! Keep up the good work.',
                    hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                    border: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
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
                    onPressed: _submitting ? null : _submitReward,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.imperialGold,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _submitting
                        ? const SizedBox(
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
      ),
    );
  }
}
