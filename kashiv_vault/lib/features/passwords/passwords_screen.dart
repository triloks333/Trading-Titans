import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/vault_models.dart';
import '../../providers.dart';

class PasswordsScreen extends ConsumerStatefulWidget {
  const PasswordsScreen({super.key, this.compose = false});
  final bool compose;
  @override
  ConsumerState<PasswordsScreen> createState() => _PasswordsScreenState();
}

class _PasswordsScreenState extends ConsumerState<PasswordsScreen> {
  String query = '';
  bool _composeHandled = false;
  @override
  Widget build(BuildContext context) {
    if (widget.compose && !_composeHandled) {
      _composeHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => edit());
    }
    final entries = ref.watch(passwordsProvider);
    final member = ref.watch(memberProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Password vault'),
        actions: [
          IconButton(
            tooltip: 'Security policy',
            onPressed: policy,
            icon: const Icon(Icons.shield_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: member?.canWrite == true
          ? FloatingActionButton.extended(
              onPressed: () => edit(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add password'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
            child: TextField(
              onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search passwords',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          if (member?.isOwner == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Owner oversight is active. Company policy permits owners to view all workspace and personal entries.',
                        style: TextStyle(fontSize: 12.5, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: entries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Could not load passwords\n$e',
                  textAlign: TextAlign.center,
                ),
              ),
              data: (items) {
                final shown = items
                    .where(
                      (e) =>
                          query.isEmpty ||
                          [e.title, e.website, e.username, e.email]
                              .whereType<String>()
                              .any((v) => v.toLowerCase().contains(query)),
                    )
                    .toList();
                if (shown.isEmpty) {
                  return _Empty(
                    onAdd: member?.canWrite == true ? () => edit() : null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(passwordsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 2, 18, 100),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PasswordTile(
                        entry: shown[i],
                        canWrite: member?.canWrite == true,
                        onEdit: () => edit(shown[i]),
                        onDelete: () => remove(shown[i]),
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

  Future<void> edit([PasswordEntry? entry]) async {
    final values = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PasswordForm(
        entry: entry,
        generate: ref.read(repositoryProvider).generatePassword,
      ),
    );
    if (values == null) return;
    try {
      await ref
          .read(repositoryProvider)
          .savePassword(id: entry?.id, values: values);
      ref.invalidate(passwordsProvider);
      ref.invalidate(activityProvider);
      info(entry == null ? 'Password saved' : 'Password updated');
    } catch (e) {
      info('Could not save: $e');
    }
  }

  Future<void> remove(PasswordEntry entry) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete password?'),
        content: Text('${entry.title} will be permanently deleted.'),
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
    await ref.read(repositoryProvider).deletePassword(entry);
    ref.invalidate(passwordsProvider);
    ref.invalidate(activityProvider);
  }

  void policy() => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Workspace security policy'),
      content: const Text(
        'Passwords are protected by authenticated access, Supabase row-level policies, TLS in transit, and provider-managed disk encryption. Owners have disclosed administrative visibility over all entries. Do not store credentials here unless you accept this company-managed access model.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Understood'),
        ),
      ],
    ),
  );
  void info(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }
}

class _PasswordTile extends StatefulWidget {
  const _PasswordTile({
    required this.entry,
    required this.canWrite,
    required this.onEdit,
    required this.onDelete,
  });
  final PasswordEntry entry;
  final bool canWrite;
  final VoidCallback onEdit, onDelete;
  @override
  State<_PasswordTile> createState() => _PasswordTileState();
}

class _PasswordTileState extends State<_PasswordTile> {
  bool visible = false;
  void copy(String label, String? value) {
    if (value == null || value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return VaultCard(
      padding: const EdgeInsets.all(13),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  e.title.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      e.username ?? e.email ?? e.website ?? 'Credential',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (e.scope == 'personal')
                const Tooltip(
                  message: 'Personal entry',
                  child: Icon(Icons.person_outline_rounded, size: 19),
                ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') widget.onEdit();
                  if (v == 'delete') widget.onDelete();
                  if (v == 'open' && e.url != null) {
                    launchUrl(Uri.parse(e.url!));
                  }
                },
                itemBuilder: (_) => [
                  if (e.url != null && e.url!.isNotEmpty)
                    const PopupMenuItem(
                      value: 'open',
                      child: Text('Open website'),
                    ),
                  if (widget.canWrite)
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (widget.canWrite)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    visible ? e.secret : '••••••••••••',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: visible ? 'Hide' : 'Show',
                  onPressed: () => setState(() => visible = !visible),
                  icon: Icon(
                    visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copy password',
                  onPressed: () => copy('Password', e.secret),
                  icon: const Icon(Icons.copy_rounded, size: 19),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({this.entry, required this.generate});
  final PasswordEntry? entry;
  final String Function({int length}) generate;
  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  late final title = TextEditingController(text: widget.entry?.title);
  late final website = TextEditingController(text: widget.entry?.website);
  late final username = TextEditingController(text: widget.entry?.username);
  late final email = TextEditingController(text: widget.entry?.email);
  late final secret = TextEditingController(text: widget.entry?.secret);
  late final url = TextEditingController(text: widget.entry?.url);
  late final notes = TextEditingController(text: widget.entry?.notes);
  late String scope = widget.entry?.scope ?? 'company';
  bool hidden = true;
  @override
  void dispose() {
    for (final c in [title, website, username, email, secret, url, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  int get strength {
    var n = 0;
    final p = secret.text;
    if (p.length >= 12) n++;
    if (RegExp('[A-Z]').hasMatch(p) && RegExp('[a-z]').hasMatch(p)) n++;
    if (RegExp(r'\d').hasMatch(p)) n++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) n++;
    return n;
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
            widget.entry == null ? 'Add password' : 'Edit password',
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
                label: Text('Personal'),
                icon: Icon(Icons.person_outline),
              ),
            ],
            selected: {scope},
            onSelectionChanged: (v) => setState(() => scope = v.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: title,
            decoration: const InputDecoration(
              labelText: 'Name *',
              hintText: 'Google Workspace',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: website,
            decoration: const InputDecoration(labelText: 'Website / App'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: username,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: secret,
            obscureText: hidden,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Password *',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Generate',
                    onPressed: () =>
                        setState(() => secret.text = widget.generate()),
                    icon: const Icon(Icons.auto_awesome_rounded),
                  ),
                  IconButton(
                    onPressed: () => setState(() => hidden = !hidden),
                    icon: Icon(
                      hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: List.generate(
              4,
              (i) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i == 3 ? 0 : 5),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < strength
                        ? (strength >= 3 ? Colors.green : Colors.orange)
                        : Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: notes,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty || secret.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Name and password are required'),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'title': title.text.trim(),
                'website': website.text.trim(),
                'username': username.text.trim(),
                'email': email.text.trim(),
                'secret': secret.text,
                'url': url.text.trim(),
                'notes': notes.text.trim(),
                'scope': scope,
              });
            },
            child: const Text('Save password'),
          ),
        ],
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({this.onAdd});
  final VoidCallback? onAdd;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.password_rounded,
            size: 58,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 18),
          Text(
            'No passwords saved',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep company credentials organized and easy to find.',
            textAlign: TextAlign.center,
          ),
          if (onAdd != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add password'),
            ),
          ],
        ],
      ),
    ),
  );
}
