import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import 'stock_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final rows = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _notifications = (rows as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllAsRead() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await Supabase.instance.client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', user.id)
        .eq('is_read', false);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read')),
      );
    }
  }

  Future<void> _markAsRead(String id) async {
    await Supabase.instance.client
        .from('notifications')
        .update({'is_read': true}).eq('id', id);
    await _load();
  }

  int get _unreadCount =>
      _notifications.where((n) => n['is_read'] != true).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text(
                'Mark all read',
                style: GoogleFonts.inter(
                  color: AppColors.imperialGold,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _notifications.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none,
                                size: 48, color: AppColors.ink5),
                            const SizedBox(height: AppSpacing.md),
                            Text('No notifications yet',
                                style:
                                    GoogleFonts.inter(color: AppColors.ink4)),
                            const SizedBox(height: 4),
                            Text(
                              'You\'ll see order updates here',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: AppColors.ink5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) =>
                        _buildNotificationTile(_notifications[index]),
                  ),
      ),
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> n) {
    final isRead = n['is_read'] == true;
    final title = n['title'] as String? ?? '';
    final body = n['body'] as String? ?? '';
    final createdAt = n['created_at'] as String?;
    final id = n['id'] as String;

    Map<String, dynamic>? actionDataMap;
    final rawActionData = n['action_data'];
    if (rawActionData != null) {
      if (rawActionData is Map) {
        actionDataMap = Map<String, dynamic>.from(rawActionData);
      } else if (rawActionData is String) {
        try {
          actionDataMap = Map<String, dynamic>.from(jsonDecode(rawActionData));
        } catch (_) {}
      }
    }
    final imageUrl = actionDataMap?['image_url'] as String?;

    String timeAgo = '';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        final diff = DateTime.now().toUtc().difference(dt);
        if (diff.inMinutes < 1) {
          timeAgo = 'Just now';
        } else if (diff.inMinutes < 60) {
          timeAgo = '${diff.inMinutes}m ago';
        } else if (diff.inHours < 24) {
          timeAgo = '${diff.inHours}h ago';
        } else {
          timeAgo = '${diff.inDays}d ago';
        }
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: isRead ? AppColors.pureWhite : AppColors.goldPale,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isRead ? AppColors.birch : AppColors.goldBorder,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color:
                isRead ? AppColors.cream : AppColors.imperialGold.withAlpha(25),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _iconForTitle(title),
            size: 20,
            color: isRead ? AppColors.ink4 : AppColors.imperialGold,
          ),
        ),
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
            fontSize: 14,
            color: AppColors.ink,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              body,
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: const EdgeInsets.all(AppSpacing.md),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          InteractiveViewer(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(imageUrl, fit: BoxFit.contain),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 30),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              timeAgo,
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink5),
            ),
          ],
        ),
        trailing: !isRead
            ? GestureDetector(
                onTap: () => _markAsRead(id),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.imperialGold,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : null,
        onTap: () {
          if (!isRead) _markAsRead(id);
          final actionType = n['action_type'] as String?;
          final actionData = n['action_data'];
          if (actionType == 'order' && actionData != null) {
            Map<String, dynamic>? data;
            if (actionData is Map) {
              data = Map<String, dynamic>.from(actionData);
            } else if (actionData is String) {
              try {
                data = Map<String, dynamic>.from(jsonDecode(actionData));
              } catch (_) {}
            }
            if (data != null) {
              final symbol = data['symbol'] as String?;
              final market = data['market'] as String? ?? 'stock';
              if (symbol != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StockDetailScreen(
                      symbol: symbol,
                      market: market,
                      name: symbol,
                    ),
                  ),
                );
              }
            }
          } else {
            // Show full notification details in a premium modal bottom sheet
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: AppColors.pureWhite,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
              ),
              builder: (context) => SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Container(
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
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration:       BoxDecoration(
                                color: AppColors.goldPale,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.notifications_outlined, size: 16, color: AppColors.goldDeep),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              timeAgo,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.ink4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.35,
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              body,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: AppColors.ink2,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                        if (imageUrl != null && imageUrl.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  insetPadding: const EdgeInsets.all(AppSpacing.md),
                                  child: Stack(
                                    alignment: Alignment.topRight,
                                    children: [
                                      InteractiveViewer(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.network(imageUrl, fit: BoxFit.contain),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white, size: 30),
                                        onPressed: () => Navigator.of(context).pop(),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side:       BorderSide(color: AppColors.birch),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              'Close',
                              style: GoogleFonts.inter(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  IconData _iconForTitle(String title) {
    final t = title.toLowerCase();
    if (t.contains('executed') || t.contains('filled')) {
      return Icons.check_circle_outline;
    }
    if (t.contains('pending') || t.contains('placed')) {
      return Icons.schedule;
    }
    if (t.contains('cancel')) return Icons.cancel_outlined;
    return Icons.notifications_outlined;
  }
}
