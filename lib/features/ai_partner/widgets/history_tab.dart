import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../ai_partner_providers.dart';
import '../../../services/ai_partner_service.dart';

class HistoryTab extends ConsumerStatefulWidget {
  const HistoryTab({super.key});

  @override
  ConsumerState<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<HistoryTab> {
  final _searchController = TextEditingController();

  static const _categories = ['all', 'grammar', 'spelling', 'naturalness'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _categoryColor(String cat) {
    switch (cat) {
      case 'spelling':
        return const Color(0xFFEC4899);
      case 'naturalness':
        return AppColors.secondary;
      default:
        return AppColors.warning;
    }
  }

  String _categoryLabel(String cat) {
    switch (cat) {
      case 'all':
        return 'All';
      case 'spelling':
        return 'Spelling';
      case 'naturalness':
        return 'Naturalness';
      default:
        return 'Grammar';
    }
  }

  @override
  Widget build(BuildContext context) {
    final historyState = ref.watch(correctionHistoryProvider);
    final notifier = ref.read(correctionHistoryProvider.notifier);

    return Column(
      children: [
        // ── Search ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search corrections…',
              prefixIcon:
                  const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        notifier.setSearch('');
                      },
                    )
                  : null,
              isDense: true,
            ),
            onChanged: notifier.setSearch,
          ),
        ),
        // ── Category filter chips ─────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: _categories.map((cat) {
              final selected = historyState.selectedCategory == cat;
              final color =
                  cat == 'all' ? AppColors.primary : _categoryColor(cat);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(_categoryLabel(cat)),
                  selected: selected,
                  selectedColor: color.withOpacity(0.18),
                  checkmarkColor: color,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? color : AppColors.textSecondary,
                  ),
                  side: BorderSide(
                      color: selected ? color : AppColors.border, width: 1.5),
                  onSelected: (_) => notifier.setCategory(cat),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 1),
        // ── List ──────────────────────────────────────────────────────────
        Expanded(
          child: historyState.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : historyState.corrections.isEmpty
                  ? _EmptyHistory(
                      query: historyState.searchQuery,
                      category: historyState.selectedCategory)
                  : _CorrectionList(
                      corrections: historyState.corrections,
                      notifier: notifier,
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _CorrectionList extends StatelessWidget {
  final List<CorrectionData> corrections;
  final HistoryNotifier notifier;
  const _CorrectionList(
      {required this.corrections, required this.notifier});

  @override
  Widget build(BuildContext context) {
    // Group by date
    final grouped = <String, List<CorrectionData>>{};
    for (final c in corrections) {
      // We don't have createdAt on CorrectionData model yet – use 'Today' as fallback key
      grouped.putIfAbsent('Today', () => []).add(c);
    }
    final dates = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: dates.length * 2,
      itemBuilder: (ctx, i) {
        final dateIdx = i ~/ 2;
        final isHeader = i % 2 == 0;
        final date = dates[dateIdx];
        if (isHeader) {
          return Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              date,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textTertiary,
                letterSpacing: 0.8,
              ),
            ),
          );
        }
        final group = grouped[date]!;
        return Column(
          children: group
              .map((c) => _CorrectionTile(correction: c, notifier: notifier))
              .toList(),
        );
      },
    );
  }
}

class _CorrectionTile extends StatelessWidget {
  final CorrectionData correction;
  final HistoryNotifier notifier;
  const _CorrectionTile({required this.correction, required this.notifier});

  Color get _color {
    switch (correction.category) {
      case 'spelling':
        return const Color(0xFFEC4899);
      case 'naturalness':
        return AppColors.secondary;
      default:
        return AppColors.warning;
    }
  }

  String get _label {
    switch (correction.category) {
      case 'spelling':
        return 'Spelling';
      case 'naturalness':
        return 'Naturalness';
      default:
        return 'Grammar';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_label,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _color)),
                  ),
                  if (correction.userNote != null &&
                      correction.userNote!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.note_alt_outlined,
                        size: 13, color: AppColors.primaryLight),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              // Original (struck through)
              Text(
                correction.original,
                style: const TextStyle(
                  fontSize: 13,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: AppColors.error,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              // Corrected
              Text(
                correction.corrected,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 6),
              // Explanation preview
              Text(
                correction.explanation,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CorrectionDetailSheet(
          correction: correction, notifier: notifier),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _CorrectionDetailSheet extends StatefulWidget {
  final CorrectionData correction;
  final HistoryNotifier notifier;
  const _CorrectionDetailSheet(
      {required this.correction, required this.notifier});

  @override
  State<_CorrectionDetailSheet> createState() =>
      _CorrectionDetailSheetState();
}

class _CorrectionDetailSheetState
    extends State<_CorrectionDetailSheet> {
  late TextEditingController _noteCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _noteCtrl =
        TextEditingController(text: widget.correction.userNote ?? '');
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    if (widget.correction.id == null) return;
    setState(() => _saving = true);
    await widget.notifier.updateNote(widget.correction.id!, _noteCtrl.text);
    setState(() => _saving = false);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.correction;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Fixement Detail',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            _DetailRow(label: 'Original',
                child: Text(c.original,
                    style: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                        decorationColor: AppColors.error,
                        color: AppColors.textSecondary,
                        fontSize: 14))),
            const SizedBox(height: 12),
            _DetailRow(label: 'Corrected',
                child: Text(c.corrected,
                    style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                        fontSize: 14))),
            const SizedBox(height: 12),
            _DetailRow(label: 'Explanation',
                child: Text(c.explanation,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13, height: 1.5))),
            const SizedBox(height: 16),
            const Text('My Notes',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _noteCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Add a personal reminder or note…',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveNote,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save Note'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () async {
                  if (widget.correction.id != null) {
                    await widget.notifier
                        .deleteCorrection(widget.correction.id!);
                  }
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Delete',
                    style: TextStyle(color: AppColors.error)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _DetailRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.textTertiary,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final String query;
  final String category;
  const _EmptyHistory({required this.query, required this.category});

  @override
  Widget build(BuildContext context) {
    final hasFilter = query.isNotEmpty || category != 'all';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilter ? Icons.search_off_rounded : Icons.history_outlined,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              hasFilter ? 'No results found' : 'No corrections yet',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Try a different keyword or filter.'
                  : 'Chat with the AI Partner and your mistake log will appear here.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
