import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../widgets/app_network_image.dart';
import '../../services/supabase_service.dart';
import 'wishlist_moderation_screen.dart';

class CommunityWishlistScreen extends StatefulWidget {
  const CommunityWishlistScreen({super.key});

  @override
  State<CommunityWishlistScreen> createState() => _CommunityWishlistScreenState();
}

class _CommunityWishlistScreenState extends State<CommunityWishlistScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseService _supabase = SupabaseService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _features = [];
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _checkAdminStatus();
    _fetchWishlist();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    _fetchWishlist();
  }

  Future<void> _checkAdminStatus() async {
    final profile = await _supabase.getUserProfile();
    if (mounted) {
      setState(() {
        _isAdmin = profile?.isAdmin ?? false;
      });
    }
  }

  String get _currentSort {
    switch (_tabController.index) {
      case 0:
        return 'trending';
      case 1:
        return 'top';
      case 2:
      default:
        return 'new';
    }
  }

  Future<void> _fetchWishlist() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase.getFeatureRequests(
        sortBy: _currentSort,
        includeReported: false, // Don't show reported items in public list
      );
      if (mounted) {
        setState(() {
          _features = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading wishlist: $e')),
        );
      }
    }
  }

  Future<void> _toggleUpvote(Map<String, dynamic> feature) async {
    final id = feature['id'] as String;
    final currentlyUpvoted = feature['user_upvoted'] as bool;
    final currentCount = feature['upvotes_count'] as int;

    // Optimistic UI Update
    setState(() {
      feature['user_upvoted'] = !currentlyUpvoted;
      feature['upvotes_count'] = currentlyUpvoted ? currentCount - 1 : currentCount + 1;
      // Resort if we are on 'top' tab
      if (_currentSort == 'top') {
        _features.sort((a, b) => (b['upvotes_count'] as int).compareTo(a['upvotes_count'] as int));
      }
    });

    try {
      await _supabase.toggleUpvote(id, !currentlyUpvoted);
    } catch (e) {
      // Revert optimistic update on failure
      if (mounted) {
        setState(() {
          feature['user_upvoted'] = currentlyUpvoted;
          feature['upvotes_count'] = currentCount;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update vote: $e')),
        );
      }
    }
  }

  Future<void> _reportFeature(String id) async {
    try {
      await _supabase.reportFeatureRequest(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you. Feature has been flagged for moderation.')),
        );
        _fetchWishlist();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reporting request: $e')),
        );
      }
    }
  }

  Future<void> _showStatusDialog(Map<String, dynamic> feature) async {
    final id = feature['id'] as String;
    String currentStatus = feature['status'] as String? ?? 'proposed';
    final versionController = TextEditingController(text: feature['released_in_version'] as String? ?? '');

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.pureWhite,
          title: Text('Update Feature Status', style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, color: AppColors.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: currentStatus,
                dropdownColor: AppColors.pureWhite,
                decoration: InputDecoration(
                  labelText: 'Status',
                  labelStyle: TextStyle(color: AppColors.ink4),
                  border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                ),
                items: const [
                  DropdownMenuItem(value: 'proposed', child: Text('Proposed')),
                  DropdownMenuItem(value: 'planned', child: Text('Planned')),
                  DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                  DropdownMenuItem(value: 'completed', child: Text('Completed (Released)')),
                  DropdownMenuItem(value: 'declined', child: Text('Declined')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() {
                      currentStatus = val;
                    });
                  }
                },
              ),
              if (currentStatus == 'completed') ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: versionController,
                  decoration: InputDecoration(
                    labelText: 'Released in Version',
                    hintText: 'e.g. v2.4.0',
                    labelStyle: TextStyle(color: AppColors.ink4),
                    border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: AppColors.ink4)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.imperialGold),
              onPressed: () async {
                final ver = currentStatus == 'completed' ? versionController.text.trim() : null;
                await _supabase.updateFeatureStatus(id, currentStatus, releasedInVersion: ver);
                if (context.mounted) Navigator.of(context).pop();
                _fetchWishlist();
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteFeature(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        title: const Text('Delete Feature Request'),
        content: const Text('Are you sure you want to permanently delete this feature request? This cannot be undone.'),
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
        _fetchWishlist();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting request: $e')),
          );
        }
      }
    }
  }

  String _getTimeAgo(String dateStr) {
    try {
      final date = DateTime.parse(dateStr).toLocal();
      final diff = DateTime.now().difference(date);
      if (diff.inDays > 365) {
        return '${(diff.inDays / 365).floor()}y ago';
      } else if (diff.inDays > 30) {
        return '${(diff.inDays / 30).floor()}mo ago';
      } else if (diff.inDays > 0) {
        return '${diff.inDays}d ago';
      } else if (diff.inHours > 0) {
        return '${diff.inHours}h ago';
      } else if (diff.inMinutes > 0) {
        return '${diff.inMinutes}m ago';
      }
      return 'just now';
    } catch (e) {
      return '';
    }
  }

  Widget _getStatusBadge(String status, String? version) {
    Color bg;
    Color text;
    String label;

    switch (status) {
      case 'completed':
        bg = AppColors.bullLight;
        text = AppColors.bull;
        label = version != null && version.isNotEmpty ? 'Released in $version' : 'Released';
        break;
      case 'in_progress':
        bg = AppColors.blueLight;
        text = AppColors.blue;
        label = 'In Progress';
        break;
      case 'planned':
        bg = AppColors.isDark ? const Color(0xFF3B2A0F) : const Color(0xFFFEF3C7);
        text = AppColors.isDark ? AppColors.crown : const Color(0xFFD97706);
        label = 'Planned';
        break;
      case 'declined':
        bg = AppColors.bearLight;
        text = AppColors.bear;
        label = 'Declined';
        break;
      case 'proposed':
      default:
        bg = AppColors.cream;
        text = AppColors.ink4;
        label = 'Proposed';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.tag),
      ),
      child: Text(
        label,
        style: GoogleFonts.ibmPlexSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: text,
          letterSpacing: 0.5,
        ),
      ),
    );
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
          'Community Wishlist',
          style: GoogleFonts.ibmPlexSans(
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.security, color: Colors.orange),
              tooltip: 'Moderation Queue',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WishlistModerationScreen()),
                );
                _fetchWishlist();
              },
            ),
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.ink),
            onPressed: _fetchWishlist,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.pureWhite,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.imperialGold,
              labelColor: AppColors.imperialGold,
              unselectedLabelColor: AppColors.ink4,
              labelStyle: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(text: 'Trending'),
                Tab(text: 'Top Voted'),
                Tab(text: 'Newest'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading && _features.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchWishlist,
                    child: _features.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            itemCount: _features.length,
                            itemBuilder: (context, index) {
                              final item = _features[index];
                              return _buildWishlistCard(item);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lightbulb_outline, size: 64, color: AppColors.ink5),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No requests here yet',
              style: GoogleFonts.ibmPlexSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Be the first to submit a request from settings!',
              style: GoogleFonts.ibmPlexSans(fontSize: 14, color: AppColors.ink4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWishlistCard(Map<String, dynamic> item) {
    final hasUpvoted = item['user_upvoted'] as bool? ?? false;
    final upvotesCount = item['upvotes_count'] as int? ?? 0;
    final dateStr = item['created_at'] as String;
    final timeAgo = _getTimeAgo(dateStr);
    final imageUrl = item['image_url'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppCard.primary.copyWith(
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Upvote button
          Column(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _toggleUpvote(item),
                icon: Icon(
                  hasUpvoted ? Icons.arrow_circle_up : Icons.arrow_circle_up_outlined,
                  size: 32,
                  color: hasUpvoted ? AppColors.imperialGold : AppColors.ink4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$upvotesCount',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: hasUpvoted ? AppColors.imperialGold : AppColors.ink2,
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.lg),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _getStatusBadge(item['status'] as String? ?? 'proposed', item['released_in_version'] as String?),
                    const Spacer(),
                    Text(
                      timeAgo,
                      style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 18, color: AppColors.ink4),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: AppColors.pureWhite,
                      onSelected: (action) {
                        if (action == 'report') {
                          _reportFeature(item['id'] as String);
                        } else if (action == 'status') {
                          _showStatusDialog(item);
                        } else if (action == 'delete') {
                          _deleteFeature(item['id'] as String);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'report',
                          child: Row(
                            children: [
                              Icon(Icons.flag_outlined, size: 18, color: Colors.orange),
                              SizedBox(width: 8),
                              Text('Report Spam'),
                            ],
                          ),
                        ),
                        if (_isAdmin) ...[
                          const PopupMenuItem(
                            value: 'status',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('Change Status'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete Request'),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item['title'] as String? ?? '',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item['description'] as String? ?? '',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: AppColors.ink3,
                  ),
                ),
                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: AppNetworkImage(
                      url: imageUrl,
                      height: 120,
                      width: double.infinity,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
