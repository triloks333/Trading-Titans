import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/vault_models.dart';
import '../../providers.dart';

const _kindIcons = {
  'document': Icons.description_outlined,
  'note': Icons.sticky_note_2_outlined,
  'todo': Icons.task_alt_rounded,
  'link': Icons.link_rounded,
  'image': Icons.image_outlined,
};

/// Bell + unread badge, shown in every main app bar so notifications are
/// reachable from any tab rather than only from Home.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final hasUnread = (notifications.value ?? const <VaultNotification>[]).any(
      (item) => !item.isRead,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () =>
                  ref.read(repositoryProvider).markNotificationsRead(),
              child: const Text('Mark all read'),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          ref.invalidate(activityProvider);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: notifications.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Notifications unavailable\n$error',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          data: (items) => ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
            children: [
              const VaultSectionTitle('For you'),
              const SizedBox(height: 10),
              if (items.isEmpty)
                _EmptyForYou()
              else
                ...items.map((item) => _NotificationTile(item: item)),
              const SizedBox(height: 24),
              const VaultSectionTitle('Workspace activity'),
              const SizedBox(height: 4),
              Text(
                'Everything the team posts, including your own uploads.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              const _ActivityFeed(),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyForYou extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return VaultCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              color: theme.colorScheme.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Nothing addressed to you yet. You are notified when someone else '
              'posts to the workspace or assigns you a task — your own posts do '
              'not notify you.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});
  final VaultNotification item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: VaultCard(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(
                  alpha: item.isRead ? .08 : .16,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _kindIcons[item.kind] ?? Icons.notifications_none_rounded,
                color: theme.colorScheme.primary,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontWeight: item.isRead
                                ? FontWeight.w600
                                : FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!item.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (item.body != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.body!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  Text(
                    DateFormat(
                      'd MMM, h:mm a',
                    ).format(item.createdAt.toLocal()),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityFeed extends ConsumerWidget {
  const _ActivityFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(activityProvider)
      .when(
        data: (feed) => feed.isEmpty
            ? const VaultCard(child: Text('No activity yet.'))
            : VaultCard(
                child: Column(
                  children: [
                    for (final entry in feed.take(12))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const CircleAvatar(
                          radius: 16,
                          child: Icon(Icons.history_rounded, size: 16),
                        ),
                        title: Text(
                          '${entry.action} ${entry.entityName ?? ''}'.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          DateFormat(
                            'd MMM, h:mm a',
                          ).format(entry.createdAt.toLocal()),
                        ),
                      ),
                  ],
                ),
              ),
        loading: () =>
            const VaultCard(child: Center(child: CircularProgressIndicator())),
        error: (_, _) => const VaultCard(child: Text('Activity unavailable')),
      );
}
