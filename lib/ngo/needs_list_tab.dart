import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ngo_providers.dart';
import 'need_bottom_sheet.dart';
import '../shared/crisis_skeleton.dart';

// ── Time-ago helper ────────────────────────────────────────

String _timeAgo(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}

Color _priorityColor(int score) {
  if (score >= 8) return const Color(0xFFFF3B30);
  if (score >= 5) return const Color(0xFFFF9500);
  return const Color(0xFF34C759);
}

const _catColors = {
  'Flood': Color(0xFF1565C0),
  'Medical': Color(0xFFC62828),
  'Fire': Color(0xFFE65100),
  'Water': Color(0xFF00838F),
  'Shelter': Color(0xFF558B2F),
  'Food': Color(0xFF6A1B9A),
  'Infrastructure': Color(0xFF4E342E),
  'Chemical': Color(0xFF37474F),
  'Search & Rescue': Color(0xFF00695C),
  'Coordination': Color(0xFF1565C0),
};

// ── Needs List Tab ─────────────────────────────────────────

class NeedsListTab extends ConsumerWidget {
  final String status;
  const NeedsListTab({super.key, required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsAsync = ref.watch(displayedNeedsProvider);
    final scheme = Theme.of(context).colorScheme;

    return needsAsync.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: 4,
        itemBuilder: (context, _) => const CrisisSkeleton(),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: scheme.error, size: 40),
              const SizedBox(height: 12),
              Text('Error loading needs',
                  style: TextStyle(color: scheme.error)),
              const SizedBox(height: 4),
              Text(e.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
      data: (allNeeds) {
        final filtered =
            allNeeds.where((n) => n.status == status).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  status == 'open'
                      ? Icons.check_circle_outline
                      : Icons.local_shipping_outlined,
                  size: 52,
                  color: scheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  status == 'open'
                      ? 'No unassigned needs right now'
                      : 'No dispatched missions yet',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: filtered.length,
          itemBuilder: (context, i) => NeedCard(need: filtered[i]),
        );
      },
    );
  }
}

// ── Need Card ──────────────────────────────────────────────

class NeedCard extends StatelessWidget {
  final NeedWithReport need;
  const NeedCard({super.key, required this.need});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final priColor = _priorityColor(need.priorityScore);
    final catColor = _catColors[need.category] ?? const Color(0xFF424242);

    return GestureDetector(
      onTap: () => showNeedBottomSheet(context, need),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Left priority accent bar ──────────────
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: priColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // ── Card content ──────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category + priority badge row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: catColor.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              need.category,
                              style: TextStyle(
                                color: catColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: priColor.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: priColor.withValues(alpha: 0.5)),
                            ),
                            child: Center(
                              child: Text(
                                '${need.priorityScore}',
                                style: TextStyle(
                                  color: priColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // AI summary (2 lines)
                      Text(
                        need.aiSummary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(height: 1.4),
                      ),
                      const SizedBox(height: 10),

                      // Skills
                      if (need.requiredSkills.isNotEmpty) ...[
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: need.requiredSkills
                                .take(3)
                                .map((s) => Padding(
                                      padding:
                                          const EdgeInsets.only(right: 5),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: scheme
                                              .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: scheme.outlineVariant
                                                  .withValues(alpha: 0.4)),
                                        ),
                                        child: Text(
                                          s.replaceAll('_', ' '),
                                          style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Footer: timestamp + dispatch button
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 13, color: scheme.outline),
                          const SizedBox(width: 4),
                          Text(
                            _timeAgo(need.reportCreatedAt),
                            style: TextStyle(
                                fontSize: 12, color: scheme.outline),
                          ),
                          const Spacer(),
                          if (need.status == 'open') ...[
                            FilledButton.icon(
                              onPressed: () =>
                                  showNeedBottomSheet(context, need),
                              icon: const Icon(Icons.send_rounded, size: 14),
                              label: const Text('Dispatch',
                                  style: TextStyle(fontSize: 12)),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                minimumSize: Size.zero,
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9500)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFFFF9500)
                                        .withValues(alpha: 0.5)),
                              ),
                              child: const Text(
                                '🚚 In Progress',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFCC7700)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
