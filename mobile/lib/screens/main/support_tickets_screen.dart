import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';

class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  final SupabaseService _supabase = SupabaseService();
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _supabase.getSupportTickets();
      setState(() {
        _tickets = data;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load tickets: $e')),
        );
      }
    }
  }

  Future<void> _toggleResolved(int index) async {
    final ticket = _tickets[index];
    final ticketId = ticket['id'] as String?;
    if (ticketId == null) return;

    final currentResolved = ticket['resolved'] as bool? ?? false;
    final newResolved = !currentResolved;

    // Optimistic update
    setState(() {
      _tickets[index] = {...ticket, 'resolved': newResolved};
    });

    try {
      await _supabase.toggleTicketResolved(ticketId, newResolved);
    } catch (e) {
      // Revert on failure
      setState(() {
        _tickets[index] = {...ticket, 'resolved': currentResolved};
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update ticket: $e')),
        );
      }
    }
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedCount = _tickets.where((t) => t['resolved'] == true).length;
    final unresolvedCount = _tickets.length - resolvedCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Submitted Tickets',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink),
        ),
        backgroundColor: AppColors.parchment,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  // Summary bar
                  if (_tickets.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.warmWhite,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.birch),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _summaryChip(Icons.inbox_outlined, '${_tickets.length}', 'Total', AppColors.ink3),
                          Container(width: 1, height: 24, color: AppColors.birch),
                          _summaryChip(Icons.error_outline, '$unresolvedCount', 'Open', AppColors.bear),
                          Container(width: 1, height: 24, color: AppColors.birch),
                          _summaryChip(Icons.check_circle_outline, '$resolvedCount', 'Resolved', AppColors.bull),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  // Ticket list
                  Expanded(
                    child: _tickets.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.mark_email_read_outlined, size: 48, color: AppColors.ink5),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  'No tickets submitted yet',
                                  style: GoogleFonts.inter(color: AppColors.ink3, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: _tickets.length,
                            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) => _buildTicketCard(index),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryChip(IconData icon, String count, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(count, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppColors.ink4)),
          ],
        ),
      ],
    );
  }

  Widget _buildTicketCard(int index) {
    final ticket = _tickets[index];
    final isFeature = ticket['type'] == 'feature';
    final isResolved = ticket['resolved'] as bool? ?? false;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isResolved ? AppColors.bullLight.withValues(alpha: 0.3) : AppColors.bearLight.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isResolved ? AppColors.bull : AppColors.bear,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isResolved ? AppColors.bull : AppColors.bear).withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: type badge + status + date
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isFeature ? AppColors.bullLight : AppColors.bearLight,
                  borderRadius: BorderRadius.circular(AppRadius.tag),
                ),
                child: Text(
                  isFeature ? 'FEATURE REQUEST' : 'BUG REPORT',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isFeature ? AppColors.bull : AppColors.bear,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Resolved/Unresolved badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isResolved
                      ? AppColors.bull.withValues(alpha: 0.1)
                      : AppColors.bear.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.tag),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isResolved ? Icons.check_circle : Icons.pending,
                      size: 10,
                      color: isResolved ? AppColors.bull : AppColors.bear,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isResolved ? 'RESOLVED' : 'OPEN',
                      style: GoogleFonts.inter(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: isResolved ? AppColors.bull : AppColors.bear,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(ticket['created_at'] as String),
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink5),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Title
          if (ticket['title'] != null && (ticket['title'] as String).isNotEmpty) ...[
            Text(
              ticket['title'] as String,
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.ink),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          // Content
          Text(
            ticket['content'] as String? ?? '',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink, height: 1.5),
          ),
          // Image attachment
          if (ticket['image_url'] != null && (ticket['image_url'] as String).isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Image.network(
                ticket['image_url'] as String,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 60,
                  color: AppColors.birch,
                  alignment: Alignment.center,
                  child: Text(
                    'Failed to load image attachment',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1, color: AppColors.birch),
          const SizedBox(height: AppSpacing.sm),
          // Bottom row: email + resolve checkbox
          Row(
            children: [
              Icon(Icons.alternate_email, size: 14, color: AppColors.ink4),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  ticket['email'] as String? ?? '',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Resolve checkbox
              GestureDetector(
                onTap: () => _toggleResolved(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isResolved
                        ? AppColors.bull.withValues(alpha: 0.12)
                        : AppColors.warmWhite,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isResolved
                          ? AppColors.bull.withValues(alpha: 0.5)
                          : AppColors.birch,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          isResolved ? Icons.check_box : Icons.check_box_outline_blank,
                          key: ValueKey(isResolved),
                          size: 18,
                          color: isResolved ? AppColors.bull : AppColors.ink4,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isResolved ? 'Resolved' : 'Mark resolved',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isResolved ? AppColors.bull : AppColors.ink3,
                        ),
                      ),
                    ],
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
