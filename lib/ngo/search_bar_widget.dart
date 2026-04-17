import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ngo_providers.dart';

const _kCategories = [
  'All',
  'Flood',
  'Medical',
  'Infrastructure',
  'Fire',
  'Water',
  'Shelter',
  'Food',
];

class SearchBarWidget extends ConsumerStatefulWidget {
  const SearchBarWidget({super.key});

  @override
  ConsumerState<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends ConsumerState<SearchBarWidget> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(searchQueryProvider.notifier).state = value.trim();
    });
    setState(() {});
  }

  void _clearSearch() {
    _controller.clear();
    _debounce?.cancel();
    ref.read(searchQueryProvider.notifier).state = '';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentQuery = ref.watch(searchQueryProvider);
    final selectedCategory = ref.watch(categoryFilterProvider);
    final scheme = Theme.of(context).colorScheme;

    final isSearchLoading = currentQuery.isNotEmpty &&
        ref.watch(searchResultsProvider).isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Search TextField ──────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: TextField(
            controller: _controller,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Search needs — e.g. "flooding near school"',
              hintStyle: TextStyle(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded,
                  color: scheme.onSurfaceVariant),
              suffixIcon: isSearchLoading
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      ),
                    )
                  : _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: _clearSearch,
                        )
                      : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // ── Category Chips ────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _kCategories.map((cat) {
              final isSelected = selectedCategory == cat ||
                  (cat == 'All' && selectedCategory == null);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(
                    cat,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (_) {
                    ref.read(categoryFilterProvider.notifier).state =
                        cat == 'All' ? null : cat;
                  },
                  backgroundColor: scheme.surfaceContainerHighest,
                  selectedColor: scheme.primaryContainer,
                  checkmarkColor: scheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected
                          ? scheme.primary.withValues(alpha: 0.5)
                          : Colors.transparent,
                    ),
                  ),
                  showCheckmark: false,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
