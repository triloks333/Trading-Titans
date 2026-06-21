import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/glossary.dart';

/// A searchable, beginner-friendly list of trading terms with plain-English
/// definitions and examples. Linked from the Profile screen and from every
/// inline term tooltip ("View all trading terms").
class GlossaryScreen extends StatefulWidget {
  const GlossaryScreen({super.key});

  @override
  State<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends State<GlossaryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GlossaryTerm> get _filtered {
    if (_query.trim().isEmpty) return Glossary.terms;
    final q = _query.trim().toLowerCase();
    return Glossary.terms
        .where((t) =>
            t.term.toLowerCase().contains(q) ||
            t.definition.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        backgroundColor: AppColors.parchment,
        elevation: 0,
        title: Text(
          'Trading Glossary',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        iconTheme: IconThemeData(color: AppColors.ink),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search terms (e.g. margin, lot, strike)',
                hintStyle: TextStyle(color: AppColors.ink4.withValues(alpha: 0.6)),
                prefixIcon: Icon(Icons.search_rounded, color: AppColors.ink4),
                filled: true,
                fillColor: AppColors.pureWhite,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: AppColors.birch),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: AppColors.birch),
                ),
              ),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      'No terms match "$_query"',
                      style: GoogleFonts.inter(color: AppColors.ink4),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                    itemCount: results.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _GlossaryCard(term: results[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _GlossaryCard extends StatelessWidget {
  final GlossaryTerm term;
  const _GlossaryCard({required this.term});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            term.term,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            term.definition,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.5,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline_rounded,
                  size: 16, color: AppColors.goldDeep),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  term.example,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.ink4,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
