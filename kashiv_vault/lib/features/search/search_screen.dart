import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/fuzzy_match.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../notes/notes_screen.dart';
import '../todos/todos_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final docs = [
      ...(ref.watch(documentsProvider('company')).value ?? []),
      ...(ref.watch(documentsProvider('personal')).value ?? []),
    ];
    final passwords = ref.watch(passwordsProvider).value ?? [];
    final links = ref.watch(linksProvider).value ?? [];
    final images = ref.watch(imagesProvider).value ?? [];
    final signatures = ref.watch(signaturesProvider).value ?? [];
    final notes = ref.watch(notesProvider).value ?? [];
    final todos = ref.watch(todosProvider).value ?? [];
    final foundDocs = docs.where(
      (e) => fuzzyMatches(query, [e.name, e.category, ...e.tags]),
    );
    final foundPasswords = passwords.where(
      (e) => fuzzyMatches(query, [e.title, e.website, e.username, e.email]),
    );
    final foundLinks = links.where(
      (e) => fuzzyMatches(query, [
        e.title,
        e.url,
        e.category,
        e.theme,
        e.description,
      ]),
    );
    final foundImages = images.where(
      (e) => fuzzyMatches(query, [e.name, e.album]),
    );
    final foundSignatures = signatures.where(
      (e) => fuzzyMatches(query, [e['name'] as String?, e['scope'] as String?]),
    );
    final foundNotes = notes.where(
      (e) => fuzzyMatches(query, [e.title, e.body, e.category, ...e.tags]),
    );
    final foundTodos = todos.where(
      (e) => fuzzyMatches(query, [e.title, e.details, e.priority]),
    );
    final count =
        foundDocs.length +
        foundPasswords.length +
        foundLinks.length +
        foundImages.length +
        foundSignatures.length +
        foundNotes.length +
        foundTodos.length;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          autofocus: true,
          onChanged: (v) => setState(() => query = v),
          decoration: const InputDecoration(
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: 'Search everything…',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              onPressed: () => setState(() => query = ''),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: query.trim().isEmpty
          ? _hint(context)
          : count == 0
          ? _none(context)
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                Text(
                  '$count results',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                if (foundDocs.isNotEmpty) ...[
                  _heading(context, 'Documents'),
                  for (final d in foundDocs)
                    _result(
                      context,
                      Icons.description_outlined,
                      d.name,
                      d.category,
                      () => ref
                          .read(repositoryProvider)
                          .openObject(
                            bucketDocuments,
                            d.storagePath,
                            d.name,
                            compressed: d.compressed,
                          ),
                    ),
                ],
                if (foundNotes.isNotEmpty) ...[
                  _heading(context, 'Notes'),
                  for (final n in foundNotes)
                    _result(
                      context,
                      Icons.sticky_note_2_outlined,
                      n.title,
                      n.category,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotesScreen()),
                      ),
                    ),
                ],
                if (foundTodos.isNotEmpty) ...[
                  _heading(context, 'Tasks'),
                  for (final t in foundTodos)
                    _result(
                      context,
                      Icons.task_alt_rounded,
                      t.title,
                      '${t.priority}${t.isDone ? ' • done' : ''}',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TodosScreen()),
                      ),
                    ),
                ],
                if (foundPasswords.isNotEmpty) ...[
                  _heading(context, 'Passwords'),
                  for (final p in foundPasswords)
                    _result(
                      context,
                      Icons.password_rounded,
                      p.title,
                      p.username ?? p.email ?? 'Credential',
                      () {
                        Clipboard.setData(ClipboardData(text: p.secret));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password copied')),
                        );
                      },
                    ),
                ],
                if (foundLinks.isNotEmpty) ...[
                  _heading(context, 'Shared content'),
                  for (final l in foundLinks)
                    _result(
                      context,
                      Icons.link_rounded,
                      l.title?.isNotEmpty == true ? l.title! : l.url,
                      l.category,
                      () => launchUrl(Uri.parse(l.url)),
                    ),
                ],
                if (foundImages.isNotEmpty) ...[
                  _heading(context, 'Images'),
                  for (final i in foundImages)
                    _result(
                      context,
                      Icons.image_outlined,
                      i.name,
                      i.album,
                      () => ref
                          .read(repositoryProvider)
                          .openObject(bucketImages, i.storagePath, i.name),
                    ),
                ],
                if (foundSignatures.isNotEmpty) ...[
                  _heading(context, 'Signatures'),
                  for (final s in foundSignatures)
                    _result(
                      context,
                      Icons.draw_outlined,
                      s['name'],
                      s['scope'],
                      () => ref
                          .read(repositoryProvider)
                          .openObject(
                            bucketSignatures,
                            s['storage_path'],
                            '${s['name']}.png',
                          ),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _heading(BuildContext context, String value) => Padding(
    padding: const EdgeInsets.only(top: 15, bottom: 8),
    child: Text(
      value,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
  Widget _result(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: VaultCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(child: Icon(icon, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
  Widget _hint(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.manage_search_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Search the whole workspace',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Documents, passwords, links, images and signatures—typos are okay.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
  Widget _none(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.search_off_rounded,
          size: 56,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 14),
        const Text('Nothing matched that search'),
      ],
    ),
  );
}
