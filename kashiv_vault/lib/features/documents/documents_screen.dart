import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/vault_models.dart';
import '../../providers.dart';
import '../notifications/notifications_screen.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key, required this.scope, this.compose = false});
  final String scope;

  /// Opens the file picker immediately (quick-action shortcut).
  final bool compose;

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  String query = '';
  String? category;
  String? selectedPersonalOwnerId;
  bool _composeHandled = false;

  @override
  Widget build(BuildContext context) {
    if (widget.compose && !_composeHandled) {
      _composeHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => upload());
    }
    final personal = widget.scope == 'personal';
    final docs = ref.watch(documentsProvider(widget.scope));
    final member = ref.watch(memberProvider).value;
    final canWrite = member?.canWrite ?? false;
    final ownerOptions = <VaultMember>[];
    if (personal && member?.isOwner == true) {
      final currentMember = member!;
      ownerOptions.addAll(
        ref.watch(membersProvider).value ?? const <VaultMember>[],
      );
      if (!ownerOptions.any((item) => item.id == currentMember.id)) {
        ownerOptions.add(currentMember);
      }
      ownerOptions.sort((a, b) {
        if (a.id == currentMember.id) return -1;
        if (b.id == currentMember.id) return 1;
        return (a.name ?? a.email).compareTo(b.name ?? b.email);
      });
    }
    final selectedOwnerId = personal
        ? (ownerOptions.any((item) => item.id == selectedPersonalOwnerId)
              ? selectedPersonalOwnerId
              : member?.id)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(personal ? 'Personal vault' : 'Company documents'),
        actions: [
          const NotificationBell(),
          IconButton(
            tooltip: 'Folders',
            onPressed: () => _info(
              'Folder management is ready in the backend and follows in the next UI phase.',
            ),
            icon: const Icon(Icons.folder_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: upload,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Upload'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
            child: Column(
              children: [
                if (personal && member?.isOwner == true) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedOwnerId),
                    initialValue: selectedOwnerId,
                    decoration: const InputDecoration(
                      labelText: 'Personal documents for',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    items: ownerOptions
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(
                              '${item.name ?? item.email}${item.id == member!.id ? ' (You)' : ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (id) => setState(() {
                      selectedPersonalOwnerId = id;
                      query = '';
                      category = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  onChanged: (v) =>
                      setState(() => query = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Search documents',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: category == null,
                        onSelected: (_) => setState(() => category = null),
                      ),
                      const SizedBox(width: 8),
                      for (final item
                          in (personal
                              ? personalCategories
                              : documentCategories)) ...[
                        ChoiceChip(
                          label: Text(item),
                          selected: category == item,
                          onSelected: (_) => setState(() => category = item),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: docs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                message: '$e',
                onRetry: () => ref.invalidate(documentsProvider(widget.scope)),
              ),
              data: (items) {
                final filtered = items
                    .where(
                      (document) =>
                          (!personal || document.ownerId == selectedOwnerId) &&
                          (category == null || document.category == category) &&
                          (query.isEmpty ||
                              document.name.toLowerCase().contains(query) ||
                              document.tags.any(
                                (tag) => tag.toLowerCase().contains(query),
                              )),
                    )
                    .toList();
                if (filtered.isEmpty) {
                  return _EmptyDocuments(
                    personal: personal,
                    onUpload: canWrite ? upload : null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(documentsProvider(widget.scope)),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DocumentTile(
                        document: filtered[i],
                        canWrite: canWrite,
                        onOpen: () => open(filtered[i]),
                        onFavorite: () => favorite(filtered[i]),
                        onDelete: () => remove(filtered[i]),
                      ),
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

  Future<void> upload() async {
    final file = (await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'png',
        'jpg',
        'jpeg',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'zip',
        'mp4',
      ],
    ))?.files.single;
    if (file == null || !mounted) return;
    final personal = widget.scope == 'personal';
    final result = await showDialog<_UploadMeta>(
      context: context,
      builder: (_) => _UploadDialog(
        fileName: file.name,
        categories: personal ? personalCategories : documentCategories,
      ),
    );
    if (result == null || !mounted) return;

    final member = ref.read(memberProvider).value;
    final members = ref.read(membersProvider).value ?? const <VaultMember>[];
    final ownerId = personal
        ? (member?.isOwner == true &&
                  members.any((item) => item.id == selectedPersonalOwnerId)
              ? selectedPersonalOwnerId
              : member?.id)
        : null;
    if (personal && ownerId == null) {
      _info('Select a member before uploading');
      return;
    }

    _loading(true);
    try {
      await ref
          .read(repositoryProvider)
          .uploadDocument(
            file: file,
            scope: widget.scope,
            category: result.category,
            ownerId: ownerId,
            expiresAt: result.expiry,
            tags: result.tags,
          );
      ref.invalidate(documentsProvider(widget.scope));
      ref.invalidate(activityProvider);
      _info('${file.name} uploaded');
    } catch (e) {
      _info('Upload failed: $e');
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).maybePop();
    }
  }

  Future<void> open(VaultDocument doc) async {
    try {
      await ref
          .read(repositoryProvider)
          .openObject(
            bucketDocuments,
            doc.storagePath,
            doc.name,
            compressed: doc.compressed,
          );
    } catch (e) {
      _info('Could not open file: $e');
    }
  }

  Future<void> favorite(VaultDocument doc) async {
    await ref.read(repositoryProvider).toggleDocument(doc);
    ref.invalidate(documentsProvider(widget.scope));
  }

  Future<void> remove(VaultDocument doc) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('${doc.name} will be permanently deleted.'),
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
    if (yes != true) return;
    try {
      await ref.read(repositoryProvider).deleteDocument(doc);
      ref.invalidate(documentsProvider(widget.scope));
      ref.invalidate(activityProvider);
    } catch (e) {
      _info('Delete failed: $e');
    }
  }

  void _loading(bool _) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  void _info(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.canWrite,
    required this.onOpen,
    required this.onFavorite,
    required this.onDelete,
  });
  final VaultDocument document;
  final bool canWrite;
  final VoidCallback onOpen, onFavorite, onDelete;
  @override
  Widget build(BuildContext context) => VaultCard(
    onTap: onOpen,
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(_icon, color: _color),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                document.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              Text(
                '${document.category}  •  ${_size(document.sizeBytes)}${document.expiresAt == null ? '' : '  •  ${DateFormat('d MMM yy').format(document.expiresAt!)}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'open') onOpen();
            if (v == 'favorite') onFavorite();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'open', child: Text('Open / preview')),
            PopupMenuItem(
              value: 'favorite',
              child: Text(
                document.isFavorite ? 'Remove favorite' : 'Add favorite',
              ),
            ),
            if (canWrite)
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
    ),
  );

  IconData get _icon {
    final ext = document.name.split('.').last.toLowerCase();
    if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
    if (['png', 'jpg', 'jpeg'].contains(ext)) return Icons.image_outlined;
    if (['xls', 'xlsx'].contains(ext)) return Icons.table_chart_outlined;
    if (ext == 'zip') return Icons.folder_zip_outlined;
    if (ext == 'mp4') return Icons.movie_outlined;
    return Icons.description_outlined;
  }

  Color get _color => document.name.toLowerCase().endsWith('.pdf')
      ? const Color(0xFFEF4444)
      : const Color(0xFF4F46E5);
  static String _size(int b) => b < 1048576
      ? '${(b / 1024).toStringAsFixed(0)} KB'
      : '${(b / 1048576).toStringAsFixed(1)} MB';
}

class _UploadMeta {
  const _UploadMeta(this.category, this.expiry, this.tags);
  final String category;
  final DateTime? expiry;
  final List<String> tags;
}

class _UploadDialog extends StatefulWidget {
  const _UploadDialog({required this.fileName, required this.categories});
  final String fileName;
  final List<String> categories;
  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<_UploadDialog> {
  late String category = widget.categories.first;
  DateTime? expiry;
  final tags = TextEditingController();
  @override
  void dispose() {
    tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Document details'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: widget.categories
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => category = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: tags,
            decoration: const InputDecoration(
              labelText: 'Tags',
              hintText: 'legal, important',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
                initialDate:
                    expiry ?? DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setState(() => expiry = d);
            },
            icon: const Icon(Icons.event_outlined),
            label: Text(
              expiry == null
                  ? 'Add expiry reminder'
                  : DateFormat('d MMMM yyyy').format(expiry!),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _UploadMeta(
            category,
            expiry,
            tags.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
          ),
        ),
        child: const Text('Upload'),
      ),
    ],
  );
}

class _EmptyDocuments extends StatelessWidget {
  const _EmptyDocuments({required this.personal, this.onUpload});
  final bool personal;
  final VoidCallback? onUpload;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            personal ? Icons.lock_outline_rounded : Icons.folder_open_rounded,
            size: 58,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 18),
          Text(
            personal ? 'Personal vault is empty' : 'No company documents yet',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            personal
                ? 'Store IDs, certificates and personal contracts here.'
                : 'Upload the first important company file.',
            textAlign: TextAlign.center,
          ),
          if (onUpload != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Upload document'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
