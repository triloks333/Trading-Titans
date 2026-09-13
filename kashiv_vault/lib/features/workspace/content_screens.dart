import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/vault_models.dart';
import '../../providers.dart';

class SharedLinksScreen extends ConsumerStatefulWidget {
  const SharedLinksScreen({super.key, this.compose = false});
  final bool compose;
  @override
  ConsumerState<SharedLinksScreen> createState() => _SharedLinksScreenState();
}

class _SharedLinksScreenState extends ConsumerState<SharedLinksScreen> {
  String query = '';
  String? theme;
  bool _composeHandled = false;

  @override
  Widget build(BuildContext context) {
    if (widget.compose && !_composeHandled) {
      _composeHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => add());
    }
    final canWrite = ref.watch(memberProvider).value?.canWrite == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Shared content')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: add,
              icon: const Icon(Icons.add_link),
              label: const Text('Add link'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
            child: TextField(
              onChanged: (v) => setState(() => query = v.toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search by title, platform or theme',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All themes'),
                    selected: theme == null,
                    onSelected: (_) => setState(() => theme = null),
                  ),
                ),
                for (final item in linkThemes)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(item),
                      selected: theme == item,
                      onSelected: (_) => setState(() => theme = item),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ref
                .watch(linksProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (links) {
                    final shown = links
                        .where(
                          (e) =>
                              (theme == null || e.theme == theme) &&
                              (query.isEmpty ||
                                  (e.title ?? '').toLowerCase().contains(
                                    query,
                                  ) ||
                                  e.url.toLowerCase().contains(query) ||
                                  e.category.toLowerCase().contains(query) ||
                                  e.theme.toLowerCase().contains(query)),
                        )
                        .toList();
                    if (shown.isEmpty) {
                      return VaultEmptyState(
                        icon: Icons.link_rounded,
                        title: theme == null
                            ? 'No shared content yet'
                            : 'Nothing filed under $theme',
                        message:
                            'Save reels, posts, articles and tools, then classify them by platform and by why they matter.',
                        actionLabel: canWrite ? 'Add link' : null,
                        onAction: canWrite ? add : null,
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 90),
                      itemCount: shown.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _LinkTile(
                          link: shown[i],
                          canWrite: canWrite,
                          onDelete: () => remove(shown[i]),
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

  Future<void> add() async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _LinkDialog(),
    );
    if (data == null) return;
    try {
      await ref.read(repositoryProvider).addLink(data);
      ref.invalidate(linksProvider);
      ref.invalidate(activityProvider);
    } catch (e) {
      info('Could not save link: $e');
    }
  }

  Future<void> remove(SharedLink link) async {
    await ref.read(repositoryProvider).deleteLink(link);
    ref.invalidate(linksProvider);
    ref.invalidate(activityProvider);
  }

  void info(String v) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v)));
    }
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.link,
    required this.canWrite,
    required this.onDelete,
  });
  final SharedLink link;
  final bool canWrite;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => VaultCard(
    onTap: () =>
        launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.link_rounded),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                link.title?.isNotEmpty == true ? link.title! : link.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _tag(
                    context,
                    link.category,
                    Theme.of(context).colorScheme.primary,
                  ),
                  _tag(context, link.theme, const Color(0xFF10B981)),
                ],
              ),
            ],
          ),
        ),
        if (canWrite)
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          )
        else
          const Icon(Icons.open_in_new_rounded, size: 19),
      ],
    ),
  );

  Widget _tag(BuildContext context, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog();
  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final url = TextEditingController(),
      title = TextEditingController(),
      description = TextEditingController();
  String category = linkCategories.first;
  String theme = linkThemes.first;
  @override
  void dispose() {
    url.dispose();
    title.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save shared link'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL *'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Where it came from'),
            items: linkCategories
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => category = v!),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: theme,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Why it matters'),
            items: linkThemes
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => theme = v!),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: description,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
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
        onPressed: () {
          var value = url.text.trim();
          if (!value.startsWith('http://') && !value.startsWith('https://')) {
            value = 'https://$value';
          }
          if (Uri.tryParse(value)?.hasAbsolutePath != true) return;
          Navigator.pop(context, {
            'url': value,
            'title': title.text.trim(),
            'description': description.text.trim(),
            'category': category,
            'theme': theme,
          });
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class ImagesScreen extends ConsumerWidget {
  const ImagesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(memberProvider).value?.canWrite == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Shared images')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => upload(context, ref),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Upload'),
            )
          : null,
      body: ref
          .watch(imagesProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (images) {
              if (images.isEmpty) {
                return const VaultEmptyState(
                  icon: Icons.collections_outlined,
                  title: 'No shared images yet',
                  message:
                      'Upload logos, posters, mockups and screenshots the whole team can reuse.',
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: .92,
                ),
                itemCount: images.length,
                itemBuilder: (_, i) => _ImageCard(
                  image: images[i],
                  canWrite: canWrite,
                  onOpen: () => ref
                      .read(repositoryProvider)
                      .openObject(
                        bucketImages,
                        images[i].storagePath,
                        images[i].name,
                      ),
                  onDelete: () async {
                    await ref.read(repositoryProvider).deleteImage(images[i]);
                    ref.invalidate(imagesProvider);
                    ref.invalidate(activityProvider);
                  },
                ),
              );
            },
          ),
    );
  }

  Future<void> upload(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result == null || !context.mounted) return;
    var album = imageAlbums.first;
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Choose album'),
        content: DropdownButtonFormField<String>(
          initialValue: album,
          items: imageAlbums
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) => album = v!,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, album),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    if (chosen == null) return;
    await ref.read(repositoryProvider).uploadImage(result.files.single, chosen);
    ref.invalidate(imagesProvider);
    ref.invalidate(activityProvider);
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.image,
    required this.canWrite,
    required this.onOpen,
    required this.onDelete,
  });
  final VaultImage image;
  final bool canWrite;
  final VoidCallback onOpen, onDelete;
  @override
  Widget build(BuildContext context) => VaultCard(
    onTap: onOpen,
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: .45),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: const Icon(Icons.image_outlined, size: 48),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 5, 9),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      image.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      image.album,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (canWrite)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SignaturesScreen extends ConsumerWidget {
  const SignaturesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(memberProvider).value?.canWrite == true;
    final body = ref
        .watch(signaturesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (items) {
            if (items.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.draw_outlined,
                      size: 58,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 14),
                    const Text('No signatures stored'),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: VaultCard(
                    onTap: () => ref
                        .read(repositoryProvider)
                        .openObject(
                          bucketSignatures,
                          item['storage_path'],
                          '${item['name']}.png',
                        ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(Icons.gesture_rounded),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                item['scope'] == 'personal'
                                    ? 'Personal signature'
                                    : 'Company signature',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.open_in_new_rounded, size: 19),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Digital signatures')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => upload(context, ref),
              icon: const Icon(Icons.draw_outlined),
              label: const Text('Add signature'),
            )
          : null,
      body: body,
    );
  }

  Future<void> upload(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.gesture_rounded),
              title: const Text('Draw signature'),
              subtitle: const Text('Sign directly on the screen'),
              onTap: () => Navigator.pop(context, 'draw'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Upload transparent PNG'),
              onTap: () => Navigator.pop(context, 'upload'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Capture from paper'),
              subtitle: const Text('Take a clear photo on a plain background'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    PlatformFile? file;
    if (source == 'upload') {
      file = (await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png'],
      ))?.files.single;
    } else if (source == 'camera') {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
        maxWidth: 1800,
      );
      if (photo != null) {
        file = PlatformFile(
          name: 'captured-signature.jpg',
          path: photo.path,
          size: await File(photo.path).length(),
        );
      }
    } else {
      file = await _drawSignature(context);
    }
    if (file == null || !context.mounted) return;

    final name = TextEditingController();
    final scope = ValueNotifier('personal');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Signature details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: scope,
              builder: (_, value, _) => SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'personal', label: Text('Personal')),
                  ButtonSegment(value: 'company', label: Text('Company')),
                ],
                selected: {value},
                onSelectionChanged: (v) => scope.value = v.first,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, name.text.trim().isNotEmpty),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(repositoryProvider)
          .uploadSignature(file, name.text.trim(), scope.value);
      ref.invalidate(signaturesProvider);
      ref.invalidate(activityProvider);
    }
    name.dispose();
    scope.dispose();
  }

  Future<PlatformFile?> _drawSignature(BuildContext context) async {
    final controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.transparent,
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Draw signature'),
        content: Container(
          height: 230,
          width: 360,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Signature(controller: controller),
        ),
        actions: [
          TextButton(onPressed: controller.clear, child: const Text('Clear')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use signature'),
          ),
        ],
      ),
    );
    if (accepted != true || controller.isEmpty) {
      controller.dispose();
      return null;
    }
    final bytes = await controller.toPngBytes();
    controller.dispose();
    if (bytes == null) return null;
    final path =
        '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}signature-${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(bytes, flush: true);
    return PlatformFile(name: 'signature.png', path: path, size: bytes.length);
  }
}
