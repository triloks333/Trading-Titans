import 'package:flutter/material.dart';

import '../../core/glossary.dart';
import '../../core/theme.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import 'glossary_quiz_screen.dart';

/// Terms matching [query] (name, definition or category) in [category].
List<GlossaryTerm> filterGlossary(String query, String category) {
  final q = query.trim().toLowerCase();
  return Glossary.terms.where((t) {
    if (category != 'All' && t.category != category) return false;
    return q.isEmpty || t.term.toLowerCase().contains(q) || t.definition.toLowerCase().contains(q) || t.category.toLowerCase().contains(q);
  }).toList();
}

/// Searchable, categorised trading terms in plain English with Indian-market
/// examples; tap a term to expand it.
class GlossaryScreen extends StatefulWidget {
  const GlossaryScreen({super.key});

  @override
  State<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends State<GlossaryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _category = 'All';
  String? _open;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terms = filterGlossary(_query, _category);
    final categories = ['All', ...Glossary.categories.where((c) => c != 'All')];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 10),
              Expanded(child: Text('Trading glossary', style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink))),
              ListenableBuilder(
                listenable: ThemeService(),
                builder: (_, _) => AuthIconButton(
                  icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  label: 'Toggle light or dark theme',
                  onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
                ),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
            child: Column(children: [
              TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                style: AppFonts.sans(size: 14, color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: 'Search ${Glossary.terms.length} terms',
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.ink4, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                          }),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final c in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: c == _category,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        labelStyle: AppFonts.sans(size: 13, weight: FontWeight.w500, color: c == _category ? AppColors.goldMid : AppColors.ink3),
                        side: BorderSide(color: c == _category ? AppColors.goldMid : AppColors.birch),
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: terms.isEmpty
                ? Center(child: Text('No terms match "${_query.trim()}".', style: AppText.body))
                : ListView(children: [for (final t in terms) _term(t)]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.lg, 16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.birch))),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GlossaryQuizScreen())),
                child: const Text('Test yourself · glossary quiz'),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _term(GlossaryTerm t) {
    final open = _open == t.term;
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        onTap: () => setState(() => _open = open ? null : t.term),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(t.term, style: AppText.bodyBold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: AppCard.badge(AppColors.cream),
                child: Text(t.category.toUpperCase(), style: AppText.badge.copyWith(color: AppColors.ink3)),
              ),
              const SizedBox(width: 6),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: AppColors.ink4),
            ]),
            if (open) ...[
              const SizedBox(height: 8),
              Text(t.definition, style: AppFonts.sans(size: 13, color: AppColors.ink3, height: 1.5)),
              if (t.example.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(t.example, style: AppFonts.sans(size: 12, color: AppColors.ink4, height: 1.5)),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}
