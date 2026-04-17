import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ngo_providers.dart';

// ── Helpers ────────────────────────────────────────────────

Color _priorityColor(int score) {
  if (score >= 8) return const Color(0xFFFF3B30);
  if (score >= 5) return const Color(0xFFFF9500);
  return const Color(0xFF34C759);
}

String _formatDistance(double meters) {
  if (meters == double.infinity || meters.isNaN) return 'Unknown distance';
  if (meters < 1000) return '${meters.toInt()} m away';
  return '${(meters / 1000).toStringAsFixed(1)} km away';
}

// ── Bottom Sheet Entry Point ───────────────────────────────

void showNeedBottomSheet(BuildContext context, NeedWithReport need) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => NeedBottomSheet(need: need),
  );
}

// ── Bottom Sheet Widget ────────────────────────────────────

class NeedBottomSheet extends ConsumerStatefulWidget {
  final NeedWithReport need;
  const NeedBottomSheet({super.key, required this.need});

  @override
  ConsumerState<NeedBottomSheet> createState() => _NeedBottomSheetState();
}

class _NeedBottomSheetState extends ConsumerState<NeedBottomSheet> {
  String? _assigningVolunteerId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final need = widget.need;
    final priColor = _priorityColor(need.priorityScore);
    final dispatchState = ref.watch(dispatchProvider);
    final volunteersAsync = ref.watch(volunteerMatchProvider(need.id));

    ref.listen<DispatchState>(dispatchProvider, (_, next) {
      if (next.success && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Volunteer dispatched successfully!'),
            backgroundColor: Color(0xFF34C759),
          ),
        );
      }
      if (next.error != null && mounted) {
        setState(() => _assigningVolunteerId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${next.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // ── Header ───────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: priColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: priColor.withValues(alpha: 0.6),
                                width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '${need.priorityScore}',
                              style: TextStyle(
                                color: priColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _CategoryBadge(category: need.category),
                              const SizedBox(height: 6),
                              Text(
                                _priorityLabel(need.priorityScore),
                                style: TextStyle(
                                    color: priColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: scheme.outline),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── AI Summary ───────────────────────
                    Text(
                      'AI Summary',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: scheme.outline),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      need.aiSummary,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 16),

                    // ── Required Skills ──────────────────
                    if (need.requiredSkills.isNotEmpty) ...[
                      Text(
                        'Skills Required',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: scheme.outline),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: need.requiredSkills
                            .map((s) => _SkillChip(skill: s))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Divider(color: scheme.outlineVariant),
                    const SizedBox(height: 12),

                    // ── Volunteer Match ──────────────────
                    Text(
                      'Nearby Available Volunteers',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    volunteersAsync.when(
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (e, _) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Could not load volunteers: $e',
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                      data: (volunteers) {
                        if (volunteers.isEmpty) {
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 24),
                            child: Column(
                              children: [
                                Icon(Icons.person_search_outlined,
                                    size: 40, color: scheme.outline),
                                const SizedBox(height: 8),
                                Text(
                                  'No available volunteers match\nthe required skills and proximity.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          );
                        }
                        return Column(
                          children: volunteers
                              .map((v) => _VolunteerTile(
                                    volunteer: v,
                                    needSkills: need.requiredSkills,
                                    isAssigning: dispatchState.isLoading &&
                                        _assigningVolunteerId == v.id,
                                    isAnyAssigning: dispatchState.isLoading,
                                    onAssign: () {
                                      setState(() =>
                                          _assigningVolunteerId = v.id);
                                      ref
                                          .read(dispatchProvider.notifier)
                                          .dispatch(
                                            needId: need.id,
                                            volunteerId: v.id,
                                          );
                                    },
                                  ))
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _priorityLabel(int score) {
    if (score >= 8) return '🔴 Critical — Immediate Response Needed';
    if (score >= 5) return '🟠 Urgent — Response Within Hours';
    return '🟢 Moderate — Standard Priority';
  }
}

// ── Volunteer Tile ─────────────────────────────────────────

class _VolunteerTile extends StatelessWidget {
  final MatchedVolunteer volunteer;
  final List<String> needSkills;
  final bool isAssigning;
  final bool isAnyAssigning;
  final VoidCallback onAssign;

  const _VolunteerTile({
    required this.volunteer,
    required this.needSkills,
    required this.isAssigning,
    required this.isAnyAssigning,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matchingSkills =
        volunteer.skills.where((s) => needSkills.contains(s)).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              volunteer.fullName.isNotEmpty
                  ? volunteer.fullName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(volunteer.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  _formatDistance(volunteer.distMeters),
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                if (matchingSkills.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: matchingSkills
                        .map((s) => _SkillChip(skill: s, highlight: true))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
            height: 36,
            child: FilledButton(
              onPressed: isAnyAssigning ? null : onAssign,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor:
                    isAssigning ? scheme.primaryContainer : scheme.primary,
              ),
              child: isAssigning
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimaryContainer),
                    )
                  : const Text('Assign', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable Small Widgets ─────────────────────────────────

class _CategoryBadge extends StatelessWidget {
  final String category;
  const _CategoryBadge({required this.category});

  static const _colors = {
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

  @override
  Widget build(BuildContext context) {
    final color = _colors[category] ?? const Color(0xFF424242);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        category,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _SkillChip extends StatelessWidget {
  final String skill;
  final bool highlight;
  const _SkillChip({required this.skill, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primaryContainer.withValues(alpha: 0.7)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        skill.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color:
              highlight ? scheme.onPrimaryContainer : scheme.onSurface,
        ),
      ),
    );
  }
}
