import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/vault_models.dart';
import '../../providers.dart';
import '../notifications/notifications_screen.dart';

class TodosScreen extends ConsumerStatefulWidget {
  const TodosScreen({super.key, this.compose = false});
  final bool compose;

  @override
  ConsumerState<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends ConsumerState<TodosScreen> {
  /// 'mine' | 'assigned' | 'done' — owners additionally get the whole board.
  String filter = 'mine';
  bool _composeHandled = false;

  @override
  Widget build(BuildContext context) {
    if (widget.compose && !_composeHandled) {
      _composeHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _edit());
    }
    final member = ref.watch(memberProvider).value;
    final todos = ref.watch(todosProvider);
    final members = ref.watch(membersProvider).value ?? const <VaultMember>[];
    final canWrite = member?.canWrite ?? false;
    final isOwner = member?.isOwner ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: const [NotificationBell(), SizedBox(width: 6)],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add_task_rounded),
              label: Text(isOwner ? 'Assign task' : 'New task'),
            )
          : null,
      body: todos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Tasks unavailable\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (items) {
          final mine = items
              .where((todo) => todo.assignedTo == member?.id && !todo.isDone)
              .toList();
          final assigned = items
              .where((todo) => todo.assignedTo != member?.id && !todo.isDone)
              .toList();
          final done = items.where((todo) => todo.isDone).toList();
          final shown = switch (filter) {
            'assigned' => assigned,
            'done' => done,
            _ => mine,
          };

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _Counter(
                        label: 'My open tasks',
                        value: '${mine.length}',
                        color: const Color(0xFF4F46E5),
                        icon: Icons.checklist_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Counter(
                        label: 'Overdue',
                        value: '${mine.where((t) => t.isOverdue).length}',
                        color: const Color(0xFFEF4444),
                        icon: Icons.schedule_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 54,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  children: [
                    _chip('mine', 'Mine (${mine.length})'),
                    if (isOwner) _chip('assigned', 'Team (${assigned.length})'),
                    _chip('done', 'Completed (${done.length})'),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? VaultEmptyState(
                        icon: Icons.task_alt_rounded,
                        title: filter == 'done'
                            ? 'Nothing completed yet'
                            : 'No open tasks',
                        message: isOwner
                            ? 'Assign work to any team member and it appears in their own task list.'
                            : 'Tasks assigned to you by an owner will show up here.',
                        actionLabel: canWrite && filter != 'done'
                            ? 'Create task'
                            : null,
                        onAction: canWrite && filter != 'done' ? _edit : null,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final todo = shown[i];
                          final assignee = members.firstWhere(
                            (item) => item.id == todo.assignedTo,
                            orElse: () => VaultMember(
                              id: todo.assignedTo,
                              email: 'Unknown member',
                              role: 'member',
                            ),
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _TodoTile(
                              todo: todo,
                              assigneeLabel: todo.assignedTo == member?.id
                                  ? 'You'
                                  : (assignee.name ?? assignee.email),
                              canWrite: canWrite,
                              onToggle: () => _toggle(todo),
                              onEdit: () => _edit(todo),
                              onDelete: () => _delete(todo),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String value, String label) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: filter == value,
      onSelected: (_) => setState(() => filter = value),
    ),
  );

  Future<void> _toggle(VaultTodo todo) async {
    try {
      await ref
          .read(repositoryProvider)
          .setTodoStatus(todo, todo.isDone ? 'open' : 'done');
      ref.invalidate(activityProvider);
    } catch (error) {
      _info('Could not update task: $error');
    }
  }

  Future<void> _edit([VaultTodo? todo]) async {
    final member = ref.read(memberProvider).value;
    if (member == null) return;
    final members = ref.read(membersProvider).value ?? const <VaultMember>[];
    final result = await showModalBottomSheet<_TodoDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TodoComposer(
        todo: todo,
        me: member,
        members: member.isAdmin ? members : const [],
      ),
    );
    if (result == null) return;
    try {
      await ref
          .read(repositoryProvider)
          .saveTodo(
            id: todo?.id,
            title: result.title,
            details: result.details,
            assignedTo: result.assignedTo,
            priority: result.priority,
            dueDate: result.dueDate,
          );
      ref.invalidate(activityProvider);
      _info(todo == null ? 'Task created' : 'Task updated');
    } catch (error) {
      _info('Could not save task: $error');
    }
  }

  Future<void> _delete(VaultTodo todo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('“${todo.title}” will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).deleteTodo(todo);
      ref.invalidate(activityProvider);
    } catch (error) {
      _info('Delete failed: $error');
    }
  }

  void _info(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label, value;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => VaultCard(
    padding: const EdgeInsets.all(13),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
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
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.todo,
    required this.assigneeLabel,
    required this.canWrite,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });
  final VaultTodo todo;
  final String assigneeLabel;
  final bool canWrite;
  final VoidCallback onToggle, onEdit, onDelete;

  static const _priorityColors = {
    'Low': Color(0xFF64748B),
    'Normal': Color(0xFF4F46E5),
    'High': Color(0xFFF59E0B),
    'Urgent': Color(0xFFEF4444),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _priorityColors[todo.priority] ?? theme.colorScheme.primary;
    return VaultCard(
      onTap: canWrite ? onEdit : null,
      padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
      child: Row(
        children: [
          Checkbox(
            value: todo.isDone,
            onChanged: canWrite ? (_) => onToggle() : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  todo.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: todo.isDone ? TextDecoration.lineThrough : null,
                    color: todo.isDone
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _pill(todo.priority, color),
                    _pill(
                      assigneeLabel,
                      theme.colorScheme.onSurfaceVariant,
                      outline: true,
                    ),
                    if (todo.dueDate != null)
                      _pill(
                        DateFormat('d MMM').format(todo.dueDate!),
                        todo.isOverdue
                            ? const Color(0xFFEF4444)
                            : theme.colorScheme.onSurfaceVariant,
                        outline: !todo.isOverdue,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (canWrite)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color, {bool outline = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: outline ? Colors.transparent : color.withValues(alpha: .13),
      border: outline ? Border.all(color: color.withValues(alpha: .35)) : null,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}

class _TodoDraft {
  const _TodoDraft(
    this.title,
    this.details,
    this.assignedTo,
    this.priority,
    this.dueDate,
  );
  final String title, assignedTo, priority;
  final String? details;
  final DateTime? dueDate;
}

class _TodoComposer extends StatefulWidget {
  const _TodoComposer({this.todo, required this.me, required this.members});
  final VaultTodo? todo;
  final VaultMember me;
  final List<VaultMember> members;
  @override
  State<_TodoComposer> createState() => _TodoComposerState();
}

class _TodoComposerState extends State<_TodoComposer> {
  late final title = TextEditingController(text: widget.todo?.title);
  late final details = TextEditingController(text: widget.todo?.details);
  late String assignedTo = widget.todo?.assignedTo ?? widget.me.id;
  late String priority = widget.todo?.priority ?? 'Normal';
  late DateTime? dueDate = widget.todo?.dueDate;

  @override
  void dispose() {
    title.dispose();
    details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.members.isEmpty ? [widget.me] : widget.members;
    final hasAssignee = options.any((member) => member.id == assignedTo);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 22,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.todo == null ? 'New task' : 'Edit task',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Task *',
                hintText: 'File GST return',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: hasAssignee ? assignedTo : widget.me.id,
              decoration: InputDecoration(
                labelText: 'Assign to',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                helperText: widget.members.isEmpty
                    ? 'Only owners and admins can assign to other members'
                    : null,
              ),
              items: options
                  .map(
                    (member) => DropdownMenuItem(
                      value: member.id,
                      child: Text(
                        '${member.name ?? member.email}'
                        '${member.id == widget.me.id ? ' (You)' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => assignedTo = value!),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: todoPriorities
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => priority = value!),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: details,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Details',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 1095)),
                  initialDate: dueDate ?? DateTime.now(),
                );
                if (picked != null) setState(() => dueDate = picked);
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(
                dueDate == null
                    ? 'Set due date'
                    : DateFormat('d MMMM yyyy').format(dueDate!),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('A task title is required')),
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  _TodoDraft(
                    title.text.trim(),
                    details.text.trim().isEmpty ? null : details.text.trim(),
                    assignedTo,
                    priority,
                    dueDate,
                  ),
                );
              },
              child: Text(widget.todo == null ? 'Create task' : 'Update task'),
            ),
          ],
        ),
      ),
    );
  }
}
