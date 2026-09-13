import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/vault_models.dart';
import '../../providers.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key, this.compose = false});

  /// Opens the composer immediately (used by the quick-action bar).
  final bool compose;

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String query = '';
  String scope = 'company';
  bool _composeHandled = false;

  @override
  Widget build(BuildContext context) {
    if (widget.compose && !_composeHandled) {
      _composeHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _edit());
    }
    final notes = ref.watch(notesProvider);
    final canWrite = ref.watch(memberProvider).value?.canWrite ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('New note'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
            child: Column(
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'company',
                      label: Text('Company'),
                      icon: Icon(Icons.domain_outlined),
                    ),
                    ButtonSegment(
                      value: 'personal',
                      label: Text('Private'),
                      icon: Icon(Icons.lock_outline_rounded),
                    ),
                  ],
                  selected: {scope},
                  onSelectionChanged: (value) =>
                      setState(() => scope = value.first),
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) =>
                      setState(() => query = value.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Search notes',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: notes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Notes unavailable\n$error',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (items) {
                final shown =
                    items
                        .where(
                          (note) =>
                              note.scope == scope &&
                              (query.isEmpty ||
                                  note.title.toLowerCase().contains(query) ||
                                  note.body.toLowerCase().contains(query) ||
                                  note.category.toLowerCase().contains(query)),
                        )
                        .toList()
                      ..sort((a, b) {
                        if (a.isPinned != b.isPinned) {
                          return a.isPinned ? -1 : 1;
                        }
                        return b.createdAt.compareTo(a.createdAt);
                      });
                if (shown.isEmpty) {
                  return VaultEmptyState(
                    icon: Icons.sticky_note_2_outlined,
                    title: scope == 'company'
                        ? 'No company notes yet'
                        : 'No private notes yet',
                    message: scope == 'company'
                        ? 'Capture meeting outcomes, decisions and processes the whole team can read.'
                        : 'Keep your own reminders and drafts here.',
                    actionLabel: canWrite ? 'Write a note' : null,
                    onAction: canWrite ? _edit : null,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 100),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _NoteTile(
                      note: shown[i],
                      canWrite: canWrite,
                      onTap: () => _edit(shown[i]),
                      onPin: () async {
                        await ref.read(repositoryProvider).pinNote(shown[i]);
                      },
                      onDelete: () => _delete(shown[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit([VaultNote? note]) async {
    final result = await showModalBottomSheet<_NoteDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NoteComposer(note: note, initialScope: scope),
    );
    if (result == null) return;
    try {
      await ref
          .read(repositoryProvider)
          .saveNote(
            id: note?.id,
            title: result.title,
            body: result.body,
            scope: result.scope,
            category: result.category,
            tags: result.tags,
          );
      ref.invalidate(activityProvider);
      _info(note == null ? 'Note saved' : 'Note updated');
    } catch (error) {
      _info('Could not save note: $error');
    }
  }

  Future<void> _delete(VaultNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text('“${note.title}” will be permanently deleted.'),
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
      await ref.read(repositoryProvider).deleteNote(note);
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

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.canWrite,
    required this.onTap,
    required this.onPin,
    required this.onDelete,
  });
  final VaultNote note;
  final bool canWrite;
  final VoidCallback onTap, onPin, onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return VaultCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  note.category,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (note.isPinned)
                Icon(
                  Icons.push_pin_rounded,
                  size: 17,
                  color: theme.colorScheme.primary,
                ),
              if (canWrite)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'pin') onPin();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'pin',
                      child: Text(note.isPinned ? 'Unpin' : 'Pin to top'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (note.body.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            DateFormat('d MMM yyyy, h:mm a').format(note.createdAt.toLocal()),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteDraft {
  const _NoteDraft(this.title, this.body, this.scope, this.category, this.tags);
  final String title, body, scope, category;
  final List<String> tags;
}

class _NoteComposer extends StatefulWidget {
  const _NoteComposer({this.note, required this.initialScope});
  final VaultNote? note;
  final String initialScope;
  @override
  State<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends State<_NoteComposer> {
  late final title = TextEditingController(text: widget.note?.title);
  late final body = TextEditingController(text: widget.note?.body);
  late final tags = TextEditingController(
    text: widget.note?.tags.join(', ') ?? '',
  );
  late String scope = widget.note?.scope ?? widget.initialScope;
  late String category = widget.note?.category ?? noteCategories.first;

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
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
            widget.note == null ? 'New note' : 'Edit note',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'company',
                label: Text('Company'),
                icon: Icon(Icons.domain_outlined),
              ),
              ButtonSegment(
                value: 'personal',
                label: Text('Private'),
                icon: Icon(Icons.lock_outline_rounded),
              ),
            ],
            selected: {scope},
            onSelectionChanged: (value) => setState(() => scope = value.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title *',
              hintText: 'Board meeting outcomes',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: noteCategories
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (value) => setState(() => category = value!),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: body,
            minLines: 6,
            maxLines: 14,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: tags,
            decoration: const InputDecoration(
              labelText: 'Tags',
              hintText: 'gst, vendor',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('A title is required')),
                );
                return;
              }
              Navigator.pop(
                context,
                _NoteDraft(
                  title.text.trim(),
                  body.text.trim(),
                  scope,
                  category,
                  tags.text
                      .split(',')
                      .map((tag) => tag.trim())
                      .where((tag) => tag.isNotEmpty)
                      .toList(),
                ),
              );
            },
            child: Text(widget.note == null ? 'Save note' : 'Update note'),
          ),
        ],
      ),
    ),
  );
}
