import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../documents/documents_screen.dart';
import '../notes/notes_screen.dart';
import '../notifications/notifications_screen.dart';
import '../passwords/passwords_screen.dart';
import '../search/search_screen.dart';
import '../todos/todos_screen.dart';
import '../workspace/content_screens.dart';
import '../workspace/workspace_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

/// Tabs that own a direct add button: Company (1), Personal (2), Tasks (3).
/// Those must keep their own button, otherwise adding a document or task turns
/// into a two-step detour through the shortcut strip.
const Set<int> tabsWithOwnAddButton = {1, 2, 3};

bool showQuickAddFor(int tabIndex) => !tabsWithOwnAddButton.contains(tabIndex);

class _HomeShellState extends ConsumerState<HomeShell> {
  int index = 0;
  bool quickOpen = false;

  bool get _showQuickAdd => showQuickAddFor(index);

  @override
  void initState() {
    super.initState();
    // The shell only mounts once the member row is loaded, so the token can be
    // attributed to a real vault member here.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(pushServiceProvider).register(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardScreen(onNavigate: (value) => setState(() => index = value)),
      const DocumentsScreen(scope: 'company'),
      const DocumentsScreen(scope: 'personal'),
      const TodosScreen(),
      const WorkspaceScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: index, children: pages),
          if (quickOpen && _showQuickAdd)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => quickOpen = false),
                child: ColoredBox(color: Colors.black.withValues(alpha: .35)),
              ),
            ),
        ],
      ),
      // Company / Personal / Tasks own their add button, so the shortcut strip
      // only appears on the tabs that have no add action of their own.
      floatingActionButton: _showQuickAdd
          ? _QuickActions(
              open: quickOpen,
              onToggle: () => setState(() => quickOpen = !quickOpen),
              onAction: _runQuickAction,
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() {
          index = value;
          quickOpen = false;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.domain_outlined),
            selectedIcon: Icon(Icons.domain_rounded),
            label: 'Company',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Personal',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist_rounded),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }

  void _runQuickAction(_QuickAction action) {
    setState(() => quickOpen = false);
    final page = switch (action) {
      _QuickAction.document => const DocumentsScreen(
        scope: 'company',
        compose: true,
      ),
      _QuickAction.personalDocument => const DocumentsScreen(
        scope: 'personal',
        compose: true,
      ),
      _QuickAction.note => const NotesScreen(compose: true),
      _QuickAction.task => const TodosScreen(compose: true),
      _QuickAction.link => const SharedLinksScreen(compose: true),
      _QuickAction.password => const PasswordsScreen(compose: true),
      _QuickAction.image => const ImagesScreen(),
      _QuickAction.signature => const SignaturesScreen(),
    };
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

enum _QuickAction {
  document,
  personalDocument,
  note,
  task,
  link,
  password,
  image,
  signature,
}

/// Plus button that fans a horizontal, staggered strip of shortcuts out of the
/// navigation bar so the "More" screen is no longer the only way in.
class _QuickActions extends StatefulWidget {
  const _QuickActions({
    required this.open,
    required this.onToggle,
    required this.onAction,
  });
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<_QuickAction> onAction;

  @override
  State<_QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends State<_QuickActions>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    duration: const Duration(milliseconds: 340),
    reverseDuration: const Duration(milliseconds: 220),
    vsync: this,
  );

  static const _items = <(_QuickAction, IconData, String)>[
    (_QuickAction.document, Icons.upload_file_rounded, 'Document'),
    (_QuickAction.personalDocument, Icons.badge_outlined, 'Personal'),
    (_QuickAction.note, Icons.sticky_note_2_outlined, 'Note'),
    (_QuickAction.task, Icons.add_task_rounded, 'Task'),
    (_QuickAction.link, Icons.add_link_rounded, 'Link'),
    (_QuickAction.password, Icons.password_rounded, 'Password'),
    (_QuickAction.image, Icons.image_outlined, 'Image'),
    (_QuickAction.signature, Icons.draw_outlined, 'Signature'),
  ];

  @override
  void didUpdateWidget(_QuickActions old) {
    super.didUpdateWidget(old);
    if (widget.open != old.open) {
      widget.open ? controller.forward() : controller.reverse();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizeTransition(
          sizeFactor: CurvedAnimation(
            parent: controller,
            curve: Curves.easeOutCubic,
          ),
          axisAlignment: 1,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width - 32,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      _AnimatedShortcut(
                        animation: controller,
                        // Right-most shortcut appears first, nearest the button.
                        order: _items.length - 1 - i,
                        total: _items.length,
                        icon: _items[i].$2,
                        label: _items[i].$3,
                        onTap: () => widget.onAction(_items[i].$1),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        FloatingActionButton(
          onPressed: widget.onToggle,
          tooltip: widget.open ? 'Close shortcuts' : 'Quick add',
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
          child: AnimatedRotation(
            turns: widget.open ? 0.375 : 0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            child: const Icon(Icons.add_rounded, size: 28),
          ),
        ),
      ],
    );
  }
}

class _AnimatedShortcut extends StatelessWidget {
  const _AnimatedShortcut({
    required this.animation,
    required this.order,
    required this.total,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final Animation<double> animation;
  final int order, total;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = (order / total) * 0.55;
    final curve = CurvedAnimation(
      parent: animation,
      curve: Interval(
        start,
        (start + 0.45).clamp(0.0, 1.0),
        curve: Curves.easeOutBack,
      ),
    );
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Interval(start, 1)),
      child: ScaleTransition(
        scale: curve,
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: theme.cardTheme.color,
                elevation: 3,
                shadowColor: Colors.black.withValues(alpha: .2),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: Icon(icon, color: theme.colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(memberProvider).value;
    final company = ref.watch(documentsProvider('company')).value ?? [];
    final personal = ref.watch(documentsProvider('personal')).value ?? [];
    final passwords = ref.watch(passwordsProvider).value ?? [];
    final notes = ref.watch(notesProvider).value ?? [];
    final todos = ref.watch(todosProvider).value ?? [];
    final activity = ref.watch(activityProvider);
    final myOpenTasks = todos
        .where((todo) => todo.assignedTo == member?.id && !todo.isDone)
        .length;
    final expiring = [...company, ...personal]
        .where(
          (document) =>
              document.expiresAt != null &&
              document.expiresAt!.isBefore(
                DateTime.now().add(const Duration(days: 30)),
              ),
        )
        .length;
    final storage = [
      ...company,
      ...personal,
    ].fold<int>(0, (sum, document) => sum + document.sizeBytes);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _greeting(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(member?.name?.split(' ').first ?? 'Kashivwealth'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search everything',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
            icon: const Icon(Icons.search_rounded),
          ),
          const NotificationBell(),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshVault(ref);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
          children: [
            _Hero(
              documents: company.length + personal.length,
              credentials: passwords.length,
              tasks: myOpenTasks,
            ),
            const SizedBox(height: 24),
            const VaultSectionTitle('Overview'),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.55,
              children: [
                _Metric(
                  icon: Icons.folder_copy_outlined,
                  label: 'Documents',
                  value: '${company.length + personal.length}',
                  color: const Color(0xFF4F46E5),
                ),
                _Metric(
                  icon: Icons.checklist_rounded,
                  label: 'My open tasks',
                  value: '$myOpenTasks',
                  color: const Color(0xFF0EA5E9),
                ),
                _Metric(
                  icon: Icons.sticky_note_2_outlined,
                  label: 'Notes',
                  value: '${notes.length}',
                  color: const Color(0xFF8B5CF6),
                ),
                _Metric(
                  icon: Icons.key_outlined,
                  label: 'Passwords',
                  value: '${passwords.length}',
                  color: const Color(0xFFF59E0B),
                ),
                _Metric(
                  icon: Icons.event_outlined,
                  label: 'Expiring soon',
                  value: '$expiring',
                  color: const Color(0xFFEF4444),
                ),
                _Metric(
                  icon: Icons.cloud_outlined,
                  label: 'Storage used',
                  value: _bytes(storage),
                  color: const Color(0xFF10B981),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const VaultSectionTitle('Jump back in'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Quick(
                    icon: Icons.domain_rounded,
                    label: 'Company',
                    onTap: () => onNavigate(1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Quick(
                    icon: Icons.checklist_rounded,
                    label: 'Tasks',
                    onTap: () => onNavigate(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Quick(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Notes',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotesScreen()),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const VaultSectionTitle('Recent activity'),
            const SizedBox(height: 12),
            activity.when(
              data: (items) => VaultCard(
                child: items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(
                          child: Text('Activity will appear here.'),
                        ),
                      )
                    : Column(
                        children: [
                          for (final item in items.take(5))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                child: Icon(
                                  _activityIcon(item.action),
                                  size: 19,
                                ),
                              ),
                              title: Text(
                                '${_capital(item.action)} ${item.entityName ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                DateFormat(
                                  'd MMM, h:mm a',
                                ).format(item.createdAt.toLocal()),
                              ),
                            ),
                        ],
                      ),
              ),
              loading: () => const VaultCard(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) =>
                  const VaultCard(child: Text('Activity unavailable')),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    return hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
  }

  static String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  static String _capital(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  static IconData _activityIcon(String action) => action.contains('upload')
      ? Icons.upload_rounded
      : action.contains('delete')
      ? Icons.delete_outline_rounded
      : action.contains('task')
      ? Icons.task_alt_rounded
      : action.contains('post')
      ? Icons.sticky_note_2_outlined
      : Icons.history_rounded;
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.documents,
    required this.credentials,
    required this.tasks,
  });
  final int documents, credentials, tasks;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: VaultTheme.brandGradient,
      borderRadius: BorderRadius.circular(26),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF4F46E5).withValues(alpha: .28),
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'KASHIVWEALTH VAULT',
              style: TextStyle(
                color: Color(0xFFDAD7FF),
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text(
          'Your company memory,\nalways within reach.',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 1.18,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _stat('$documents documents'),
            _stat('$credentials credentials'),
            _stat('$tasks open tasks'),
          ],
        ),
      ],
    ),
  );

  Widget _stat(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => VaultCard(
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Quick extends StatelessWidget {
  const _Quick({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => VaultCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 8),
    child: Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
