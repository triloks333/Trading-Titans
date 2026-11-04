import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';

class ReferEarnScreen extends StatefulWidget {
  const ReferEarnScreen({super.key});

  @override
  State<ReferEarnScreen> createState() => _ReferEarnScreenState();
}

class _ReferEarnScreenState extends State<ReferEarnScreen> {
  bool _loadingStats = true;
  double _claimedBalance = 0.0;
  List<Map<String, dynamic>> _referredFriends = [];

  @override
  void initState() {
    super.initState();
    _loadReferralData();
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month.toString().padLeft(2, '0')}/${dt.year.toString().substring(2)}';
  }

  Future<void> _loadReferralData() async {
    try {
      final auth = context.read<AuthService>();
      final userId = auth.user?.id;
      if (userId == null) return;

      // 1. Fetch referred profiles (friends who used this referral code during
      // signup). profiles is owner/admin-only now, so we use a SECURITY DEFINER
      // RPC that returns only id/name/created_at for people you referred.
      final friendsResponse =
          await SupabaseService().client.rpc('get_my_referrals');

      final friendsList = List<Map<String, dynamic>>.from(
        (friendsResponse as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final List<Map<String, dynamic>> mappedFriends = [];
      double totalEarned = friendsList.length * 5000.0;

      for (var friend in friendsList) {
        final friendId = friend['id'] as String;
        final friendName = friend['name'] as String;
        final date = DateTime.parse(friend['created_at'] as String).toLocal();
        final dateStr = _formatDate(date);

        mappedFriends.add({
          'id': friendId,
          'name': friendName,
          'package': 'Registered Titan account',
          'date': dateStr,
          'commission': 5000.0,
          'status': 'claimed', // Auto-claimed/credited instantly to main wallet balance on signup
        });
      }
      setState(() {
        _referredFriends = mappedFriends;
        _claimedBalance = totalEarned;
      });
    } catch (e) {
      debugPrint('Error loading referral data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingStats = false;
        });
      }
    }
  }



  void _copyToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Referral code copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final referralCode = auth.user?.referralCode ?? 'TT-XXXXXX';

    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        backgroundColor: AppColors.pureWhite,
        elevation: 0,
        leading: IconButton(
          icon:       Icon(Icons.arrow_back_ios_new, color: AppColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Refer & Earn',
          style: GoogleFonts.ibmPlexSans(
            color: AppColors.ink,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: _loadingStats
          ? Center(child: CircularProgressIndicator(color: AppColors.imperialGold))
          : RefreshIndicator(
              onRefresh: _loadReferralData,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  // Hero Referral Card
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    // Flat action blue: Titan Terminal avoids gradient washes.
                    decoration: BoxDecoration(color: AppColors.goldDeep, borderRadius: BorderRadius.circular(AppRadius.lg)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share the Titan desk,',
                          style: GoogleFonts.ibmPlexSans(
                            color: AppColors.pureWhite.withValues(alpha: 0.8),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Both Get ₹5,000 Cash!',
                          style: GoogleFonts.ibmPlexSans(
                            color: AppColors.pureWhite,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'When your friends sign up using your referral code, both of you get ₹5,000 dummy cash credited instantly and automatically to your wallet balance. No purchase required!',
                          style: GoogleFonts.ibmPlexSans(
                            color: AppColors.pureWhite.withValues(alpha: 0.9),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Referral Code Card
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.pureWhite,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.birch),
                      boxShadow: AppShadows.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR REFERRAL CODE',
                          style: GoogleFonts.ibmPlexSans(
                            color: AppColors.ink4,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.parchment,
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  border: Border.all(color: AppColors.birch),
                                ),
                                child: Text(
                                  referralCode,
                                  style: GoogleFonts.ibmPlexSans(
                                    color: AppColors.ink2,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            GestureDetector(
                              onTap: () => _copyToClipboard(referralCode),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.goldPale,
                                  border: Border.all(color: AppColors.goldBorder),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Icon(
                                  Icons.copy,
                                  size: 20,
                                  color: AppColors.goldDeep,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Mechanics and Examples
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.pureWhite,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.birch),
                      boxShadow: AppShadows.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'REFERRAL BONUS PROGRAM',
                          style: GoogleFonts.ibmPlexSans(
                            color: AppColors.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _exampleRow('Referred Friend Signup', '₹5,000 Dummy Cash (Flat)'),
                        const Divider(),
                        _exampleRow('Referrer Reward (You)', '₹5,000 Dummy Cash (Flat)'),
                        const Divider(),
                        _exampleRow('Reward Delivery', 'Credited Instantly to Wallet'),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Referral Stats
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.pureWhite,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.birch),
                      boxShadow: AppShadows.sm,
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Referral Cash Earned',
                                  style: GoogleFonts.ibmPlexSans(color: AppColors.ink4, fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppFormat.formatINR(_claimedBalance),
                                  style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.bull,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.bullLight,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_outline, color: AppColors.bull, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Auto-Redeemed',
                                    style: GoogleFonts.ibmPlexSans(
                                      color: AppColors.bull,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                          child: Divider(),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _statCol('Referred Friends Joined', '${_referredFriends.length}'),
                            _statCol('Referral Benefit', '₹5,000 per user'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Friends List
                  Text(
                    'Referred Friends & Status',
                    style: GoogleFonts.ibmPlexSans(
                      color: AppColors.ink,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_referredFriends.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        color: AppColors.pureWhite,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.birch),
                      ),
                      child: Column(
                        children: [
                                Icon(Icons.people_outline, size: 48, color: AppColors.ink4),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'No referred friends yet',
                            style: GoogleFonts.ibmPlexSans(
                              color: AppColors.ink,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Share your referral code above to start earning!',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.ibmPlexSans(
                              color: AppColors.ink4,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._referredFriends.map((friend) => _buildFriendTile(friend)),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
    );
  }

  Widget _exampleRow(String pkg, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(pkg, style: GoogleFonts.ibmPlexSans(color: AppColors.ink2, fontSize: 13, fontWeight: FontWeight.w500)),
          Text(desc, style: GoogleFonts.ibmPlexSans(color: AppColors.bull, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _statCol(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.ibmPlexSans(color: AppColors.ink4, fontSize: 12)),
        const SizedBox(height: 4),
        Text(val, style: GoogleFonts.ibmPlexSans(color: AppColors.ink, fontWeight: FontWeight.bold, fontSize: 15)),
      ],
    );
  }

  Widget _buildFriendTile(Map<String, dynamic> friend) {
    final status = friend['status'] as String;
    final commission = friend['commission'] as double;
    
    Color badgeBg;
    Color badgeText;
    String statusLabel;

    if (status == 'claimed') {
      badgeBg = AppColors.bullLight;
      badgeText = AppColors.bull;
      statusLabel = 'Claimed';
    } else if (status == 'unclaimed') {
      badgeBg = AppColors.blueLight;
      badgeText = AppColors.blue;
      statusLabel = 'Available';
    } else {
      badgeBg = AppColors.cream;
      badgeText = AppColors.ink4;
      statusLabel = 'No Purchase';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend['name'] as String,
                  style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${friend['package']} · ${friend['date']}',
                  style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (commission > 0)
                Text(
                  '+${AppFormat.formatINR(commission)}',
                  style: GoogleFonts.ibmPlexSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.bull,
                  ),
                )
              else
                Text(
                  '--',
                  style: GoogleFonts.ibmPlexSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.ink4,
                  ),
                ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeText,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
