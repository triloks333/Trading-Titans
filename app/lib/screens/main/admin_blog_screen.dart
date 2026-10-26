import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_constants.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';

/// Writes and publishes blog posts.
///
/// Lives in the app's admin panel rather than in KashiVault: KashiVault is a
/// personal vault (notes, passwords, documents) with no publishing concept at all,
/// while this panel already has the `isAdmin` gate, the image picker and the
/// Supabase session. The post is rendered server-side by `website/api/post.js`, so
/// nothing here needs to know how it will look.
class AdminBlogScreen extends StatefulWidget {
  const AdminBlogScreen({super.key});

  @override
  State<AdminBlogScreen> createState() => _AdminBlogScreenState();
}

class _AdminBlogScreenState extends State<AdminBlogScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _slug = TextEditingController();
  final _excerpt = TextEditingController();
  final _body = TextEditingController();

  static const Map<String, String> _marketOptions = {
    'all': 'All Markets (Global)',
    'stock': 'Indian Stock Market (NSE/BSE)',
    'us_stock': 'US Stocks (NASDAQ/NYSE)',
    'crypto': 'Cryptocurrency (Crypto)',
    'pakistan_stock': 'Pakistan Stocks (PSX)',
    'italy_stock': 'Italy Stocks (Borsa Italiana)',
  };

  String _selectedMarket = 'all';
  List<Map<String, dynamic>> _posts = const [];
  String? _editingId;
  String? _coverUrl;
  bool _loading = true;
  bool _saving = false;
  bool _publish = true;

  /// True once the slug has been typed by hand, after which it stops tracking the
  /// title. Otherwise editing the title of an already-published post would rewrite
  /// its URL and break every inbound link.
  bool _slugTouched = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _slug.dispose();
    _excerpt.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final posts = await SupabaseService().listBlogPosts();
    if (!mounted) return;
    setState(() {
      _posts = posts;
      _loading = false;
    });
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Title → slug. Same shape the table's CHECK enforces, so a title of pure
  /// punctuation produces an empty slug and fails validation here rather than at
  /// the database.
  static String slugify(String title) {
    final lower = title.toLowerCase();
    final cleaned = StringBuffer();
    for (final rune in lower.runes) {
      final c = String.fromCharCode(rune);
      if (RegExp(r'[a-z0-9]').hasMatch(c)) {
        cleaned.write(c);
      } else if (cleaned.isNotEmpty && !cleaned.toString().endsWith('-')) {
        cleaned.write('-');
      }
    }
    var slug = cleaned.toString();
    while (slug.endsWith('-')) {
      slug = slug.substring(0, slug.length - 1);
    }
    return slug.length > 120 ? slug.substring(0, 120) : slug;
  }

  void _reset() {
    setState(() {
      _editingId = null;
      _coverUrl = null;
      _slugTouched = false;
      _publish = true;
      _selectedMarket = 'all';
      _title.clear();
      _slug.clear();
      _excerpt.clear();
      _body.clear();
    });
  }

  void _edit(Map<String, dynamic> post) {
    final rawExcerpt = post['excerpt'] as String?;
    final match = RegExp(r'^\[market:([a-z_]+)\]\s*(.*)$', dotAll: true)
        .firstMatch(rawExcerpt ?? '');
    String cleanExcerpt = rawExcerpt ?? '';
    String market = 'all';
    if (match != null) {
      market = match.group(1) ?? 'all';
      cleanExcerpt = match.group(2) ?? '';
    }

    setState(() {
      _editingId = '${post['id']}';
      _selectedMarket = _marketOptions.containsKey(market) ? market : 'all';
      _title.text = '${post['title'] ?? ''}';
      _slug.text = '${post['slug'] ?? ''}';
      _excerpt.text = cleanExcerpt;
      _body.text = '${post['body_markdown'] ?? ''}';
      _coverUrl = post['cover_url'] as String?;
      _publish = post['published_at'] != null;
      // An existing post's slug is already public; never auto-rewrite it.
      _slugTouched = true;
    });
  }

  Future<void> _pickCover() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Compressed here because the bucket caps at 5 MB and this is also the
      // og:image, where a huge file just slows the unfurl down.
      maxWidth: 1600,
      maxHeight: 900,
      imageQuality: 82,
    );
    if (picked == null) return;
    setState(() => _saving = true);
    final Uint8List bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last.toLowerCase();
    final url = await SupabaseService().uploadBlogImage(
      bytes: bytes,
      extension: ext.isEmpty ? 'jpg' : ext,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (url != null) _coverUrl = url;
    });
    _tell(url == null ? 'That image could not be uploaded.' : 'Cover updated.');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final cleanExcerpt = _excerpt.text.trim();
    final savedExcerpt = cleanExcerpt.isEmpty
        ? (_selectedMarket == 'all' ? null : '[market:$_selectedMarket]')
        : (_selectedMarket == 'all'
            ? cleanExcerpt
            : '[market:$_selectedMarket] $cleanExcerpt');

    final error = await SupabaseService().saveBlogPost(
      id: _editingId,
      slug: _slug.text.trim(),
      title: _title.text.trim(),
      excerpt: savedExcerpt,
      bodyMarkdown: _body.text,
      coverUrl: _coverUrl,
      publish: _publish,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      _tell(error);
      return;
    }
    _tell(_publish
        ? 'Published live to app & ${AppConstants.marketingSiteUrl}/blog/${_slug.text.trim()}'
        : 'Saved as a draft.');
    _reset();
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        title: Text('Delete this post?',
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
        content: Text(
          'Anyone who has the link, and Google, will start getting a 404. This '
          'cannot be undone.',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink3, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.bear))),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await SupabaseService().deleteBlogPost('${post['id']}');
    _tell(ok ? 'Post deleted.' : 'That could not be deleted.');
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        backgroundColor: AppColors.parchment,
        centerTitle: false,
        title: Text(_editingId == null ? 'New Blog Post' : 'Edit Blog Post',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.bold, color: AppColors.ink)),
        actions: [
          if (_editingId != null)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Start a new post',
              onPressed: _reset,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _field(
              controller: _title,
              label: 'Title',
              hint: 'e.g. RBI Keeps Rates Unchanged or PSX Surges to All-Time High',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'A title is required' : null,
              onChanged: (v) {
                if (!_slugTouched) _slug.text = slugify(v);
              },
            ),
            _marketSelector(),
            _field(
              controller: _slug,
              label: 'Slug (Website Blog URL)',
              hint: 'rbi-keeps-rates-unchanged',
              helper: '${AppConstants.marketingSiteUrl}/blog/<slug>',
              onChanged: (_) => _slugTouched = true,
              validator: (v) {
                final slug = (v ?? '').trim();
                if (slug.isEmpty) return 'A slug is required';
                if (slug.length < 3) return 'Too short';
                // Mirrors the table's CHECK, so a bad slug is caught before the
                // round trip rather than coming back as a constraint error.
                if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(slug)) {
                  return 'Lowercase letters, numbers and single hyphens only';
                }
                return null;
              },
            ),
            _field(
              controller: _excerpt,
              label: 'Short Description / Excerpt',
              hint: 'One or two lines shown on home news cards and search preview.',
              maxLines: 2,
              validator: (v) => (v != null && v.length > 320)
                  ? 'Keep it under 320 characters'
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            _coverPicker(),
            const SizedBox(height: AppSpacing.md),
            _field(
              controller: _body,
              label: 'Full Article Content (Markdown)',
              hint: '## Market Impact\n\nWrite full article body here...\n\nUsers read the first 50% in-app and can tap to continue reading on the website.',
              maxLines: 16,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'The post needs a body' : null,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: AppSpacing.sm),
              child: Text(
                'Supported: # headings, **bold**, *italic*, `code`, ``` fences, '
                '- lists, 1. lists, [links](https://…) and '
                '![images](https://…). Anything else is shown as plain text.',
                style: GoogleFonts.inter(
                    fontSize: 11.5, color: AppColors.ink4, height: 1.45),
              ),
            ),
            SwitchListTile(
              value: _publish,
              onChanged: (v) => setState(() => _publish = v),
              activeThumbColor: AppColors.imperialGold,
              contentPadding: EdgeInsets.zero,
              title: Text('Published',
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
              subtitle: Text(
                _publish
                    ? 'Live and indexable as soon as you save.'
                    : 'Saved as a draft. Nobody outside this panel can read it.',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                backgroundColor: AppColors.imperialGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: Text(
                _saving
                    ? 'Saving…'
                    : (_editingId == null ? 'Create post' : 'Save changes'),
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Existing posts',
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            const SizedBox(height: AppSpacing.sm),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(),
              ))
            else if (_posts.isEmpty)
              Text('None yet.',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink4))
            else
              for (final post in _posts) _postRow(post),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helper,
    int maxLines = 1,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: validator,
        onChanged: onChanged,
        style: GoogleFonts.inter(fontSize: 14, color: AppColors.ink),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 2,
          alignLabelWithHint: maxLines > 1,
          filled: true,
          fillColor: AppColors.pureWhite,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
    );
  }

  Widget _coverPicker() {
    return Row(
      children: [
        if (_coverUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Image.network(_coverUrl!,
                width: 84, height: 56, fit: BoxFit.cover),
          )
        else
          Container(
            width: 84,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.birch),
            ),
            child: Icon(Icons.image_outlined, color: AppColors.ink5),
          ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : _pickCover,
            icon: const Icon(Icons.upload_outlined, size: 18),
            label: Text(_coverUrl == null ? 'Add cover image' : 'Replace cover',
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _marketSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Target Market Category',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.pureWhite,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.birch),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedMarket,
                isExpanded: true,
                icon: Icon(Icons.arrow_drop_down, color: AppColors.ink3),
                items: _marketOptions.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.ink,
                        fontWeight: entry.key == 'all'
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedMarket = val);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'Only users interested in this market will see this news in their home feed. "All Markets" shows to everyone.',
              style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.ink4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _postRow(Map<String, dynamic> post) {
    final published = post['published_at'] != null;
    final rawExcerpt = post['excerpt'] as String?;
    final match = RegExp(r'^\[market:([a-z_]+)\]\s*(.*)$', dotAll: true)
        .firstMatch(rawExcerpt ?? '');
    final market = match != null ? (match.group(1) ?? 'all') : 'all';
    final marketLabel = _marketOptions[market] ?? market;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warmWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.cream,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.birch),
                      ),
                      child: Text(
                        marketLabel.split(' (').first,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.imperialGold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${post['title']}',
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(
                  '/blog/${post['slug']}  ·  ${published ? 'published' : 'draft'}',
                  style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: published ? AppColors.bull : AppColors.ink4),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.ink3),
            tooltip: 'Edit',
            onPressed: () => _edit(post),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.bear),
            tooltip: 'Delete',
            onPressed: () => _delete(post),
          ),
        ],
      ),
    );
  }
}
