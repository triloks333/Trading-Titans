import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../notes/notes_screen.dart';
import '../notifications/notifications_screen.dart';
import '../passwords/passwords_screen.dart';
import '../todos/todos_screen.dart';
import 'content_screens.dart';

class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(memberProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspace'),
        actions: const [NotificationBell(), SizedBox(width: 6)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          VaultCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Text(
                    (member?.name ?? member?.email ?? 'K')
                        .substring(0, 1)
                        .toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member?.name ?? 'Kashivwealth member',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        member?.email ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(label: Text(member?.role.toUpperCase() ?? 'MEMBER')),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Workspace',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 11),
          _Menu(
            icon: Icons.sticky_note_2_outlined,
            color: const Color(0xFF8B5CF6),
            title: 'Notes',
            subtitle: 'Meetings, decisions, ideas and reminders',
            onTap: () => _open(context, const NotesScreen()),
          ),
          _Menu(
            icon: Icons.checklist_rounded,
            color: const Color(0xFF0EA5E9),
            title: 'Tasks',
            subtitle: 'Assign work and track what is open',
            onTap: () => _open(context, const TodosScreen()),
          ),
          _Menu(
            icon: Icons.password_rounded,
            color: const Color(0xFFF59E0B),
            title: 'Password vault',
            subtitle: 'Company and personal credentials',
            onTap: () => _open(context, const PasswordsScreen()),
          ),
          _Menu(
            icon: Icons.notifications_none_rounded,
            color: const Color(0xFFEF4444),
            title: 'Notifications',
            subtitle: 'Everything posted to the workspace',
            onTap: () => _open(context, const NotificationsScreen()),
          ),
          const SizedBox(height: 18),
          Text(
            'Knowledge & assets',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 11),
          _Menu(
            icon: Icons.link_rounded,
            color: const Color(0xFF2563EB),
            title: 'Shared content',
            subtitle: 'Reels, posts, articles and tools by theme',
            onTap: () => _open(context, const SharedLinksScreen()),
          ),
          _Menu(
            icon: Icons.collections_outlined,
            color: const Color(0xFFEC4899),
            title: 'Shared images',
            subtitle: 'Logos, posters, mockups and screenshots',
            onTap: () => _open(context, const ImagesScreen()),
          ),
          _Menu(
            icon: Icons.draw_outlined,
            color: const Color(0xFF8B5CF6),
            title: 'Digital signatures',
            subtitle: 'Store and export approved signatures',
            onTap: () => _open(context, const SignaturesScreen()),
          ),
          const SizedBox(height: 18),
          Text(
            'Administration',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 11),
          _Menu(
            icon: Icons.groups_outlined,
            color: const Color(0xFF10B981),
            title: 'Team & roles',
            subtitle: 'Members, access and permissions',
            onTap: () => _open(context, const TeamScreen()),
          ),
          _Menu(
            icon: Icons.history_rounded,
            color: const Color(0xFFF59E0B),
            title: 'Activity log',
            subtitle: 'Uploads, edits, downloads and logins',
            onTap: () => _open(context, const ActivityScreen()),
          ),
          _Menu(
            icon: Icons.settings_outlined,
            color: const Color(0xFF64748B),
            title: 'Settings',
            subtitle: 'Appearance, security and account',
            onTap: () => _open(context, const SettingsScreen()),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

class _Menu extends StatelessWidget {
  const _Menu({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: VaultCard(
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(memberProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team & roles'),
        actions: [
          if (me?.isAdmin == true)
            IconButton(
              tooltip: 'Invite member',
              onPressed: () => _invite(context, ref),
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: ref
          .watch(membersProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (members) => ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: members.length,
              separatorBuilder: (_, _) => const SizedBox(height: 9),
              itemBuilder: (_, i) {
                final m = members[i];
                return VaultCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        child: Text(
                          (m.name ?? m.email).substring(0, 1).toUpperCase(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.name ?? m.email,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (m.name != null)
                              Text(
                                m.email,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      if (me?.isOwner == true && m.id != me?.id)
                        DropdownButton<String>(
                          value: m.role,
                          underline: const SizedBox(),
                          items: memberRoles
                              .map(
                                (r) =>
                                    DropdownMenuItem(value: r, child: Text(r)),
                              )
                              .toList(),
                          onChanged: (role) async {
                            if (role == null) return;
                            await ref
                                .read(repositoryProvider)
                                .setRole(m.id, role);
                            ref.invalidate(membersProvider);
                          },
                        )
                      else
                        Chip(label: Text(m.role)),
                    ],
                  ),
                );
              },
            ),
          ),
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
    var role = 'member';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Invite team member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email address'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: memberRoles
                  .where((r) => r != 'owner')
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (value) => role = value!,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, email.text.contains('@')),
            child: const Text('Create invite'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      try {
        await ref.read(repositoryProvider).invite(email.text, role);
        ref.invalidate(invitesProvider);
        ref.invalidate(activityProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${email.text.trim()} can now sign in')),
          );
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Invite failed: $error')));
        }
      }
    }
    email.dispose();
  }
}

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Activity log')),
    body: ref
        .watch(activityProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (items) => items.isEmpty
              ? const Center(child: Text('No activity yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) => ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.history_rounded, size: 19),
                    ),
                    title: Text(
                      '${items[i].action} ${items[i].entityName ?? ''}',
                    ),
                    subtitle: Text(
                      items[i].createdAt.toLocal().toString().substring(0, 16),
                    ),
                  ),
                ),
        ),
  );
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Appearance',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          VaultCard(
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {selected},
              onSelectionChanged: (v) =>
                  ref.read(themeModeProvider.notifier).set(v.first),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Security',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          VaultCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.fingerprint_rounded),
                  title: const Text('Test biometric access'),
                  subtitle: const Text(
                    'Uses this device’s secure biometric prompt',
                  ),
                  onTap: () async {
                    final ok = await LocalAuthentication().authenticate(
                      localizedReason: 'Unlock KASHIVWEALTH Management Vault',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Biometric authentication succeeded'
                                : 'Authentication cancelled',
                          ),
                        ),
                      );
                    }
                  },
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.devices_outlined),
                  title: Text('Device management'),
                  subtitle: Text(
                    'Session controls prepared for the next phase',
                  ),
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.timer_outlined),
                  title: Text('Auto-lock'),
                  subtitle: Text('Locks when the system protects the app'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Account',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => ref.read(repositoryProvider).signOut(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
