import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';

class WishlistModerationScreen extends StatefulWidget {
  const WishlistModerationScreen({super.key});

  @override
  State<WishlistModerationScreen> createState() => _WishlistModerationScreenState();
}

class _WishlistModerationScreenState extends State<WishlistModerationScreen> {
  final SupabaseService _supabase = SupabaseService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _reportedRequests = [];

  @override
  void initState() {
    super.initState();
    _fetchReportedWishlist();
  }

  Future<void> _fetchReportedWishlist() async {
    setState(() => _isLoading = true);
    try {
      // Fetch wishlist requests including reported posts
      final data = await _supabase.getFeatureRequests(includeReported: true);
      // Filter list to keep only those with reports >= 3 and not moderated
      final reported = data.where((item) {
        final reportsCount = item['reports_count'] as int? ?? 0;
        final isModerated = item['is_moderated'] as bool? ?? false;
        return reportsCount >= 3 && !isModerated;
      }).toList();

      if (mounted) {
        setState(() {
          _reportedRequests = reported;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading moderation queue: $e')),
        );
      }
    }
  }

  Future<void> _approveFeature(String id) async {
    try {
      await _supabase.approveFeatureRequest(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feature marked safe and restored to feed.')),
        );
      }
      _fetchReportedWishlist();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error approving feature: $e')),
        );
      }
    }
  }

  Future<void> _deleteFeature(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        title: const Text('Delete Feature Request'),
        content: const Text('Are you sure you want to permanently delete this reported feature request? This action is irreversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: AppColors.ink4)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.deleteFeatureRequest(id);
        _fetchReportedWishlist();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting request: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        backgroundColor: AppColors.pureWhite,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Moderation Queue',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ),
      body: _isLoading && _reportedRequests.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _reportedRequests.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: _reportedRequests.length,
                  itemBuilder: (context, index) {
                    final item = _reportedRequests[index];
                    return _buildModerationCard(item);
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.gavel_outlined, size: 64, color: AppColors.bull),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Moderation queue clean!',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'All features are safe and visible.',
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.ink4),
          ),
        ],
      ),
    );
  }

  Widget _buildModerationCard(Map<String, dynamic> item) {
    final reportsCount = item['reports_count'] as int? ?? 0;
    final imageUrl = item['image_url'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppCard.primary.copyWith(
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.bearLight,
                  borderRadius: BorderRadius.circular(AppRadius.tag),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 12, color: AppColors.bear),
                    const SizedBox(width: 4),
                    Text(
                      '$reportsCount Reports',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.bear,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Status: ${item['status']}',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            item['title'] as String? ?? '',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item['description'] as String? ?? '',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.ink3,
            ),
          ),
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.network(
                imageUrl,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox(),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _approveFeature(item['id'] as String),
                  icon: const Icon(Icons.check, color: AppColors.bull),
                  label: const Text('Mark Safe', style: TextStyle(color: AppColors.bull)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.bull),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _deleteFeature(item['id'] as String),
                  icon: const Icon(Icons.delete_forever, color: Colors.white),
                  label: const Text('Delete permanently'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.bear,
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
