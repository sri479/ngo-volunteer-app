import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/role_selection_screen.dart';
import '../ngo/search_bar_widget.dart';
import '../ngo/ngo_map_tab.dart';
import '../ngo/needs_list_tab.dart';
import '../ngo/ngo_providers.dart';
import '../shared/responsive_container.dart';
import 'auth_provider.dart';

class NgoDashboardScreen extends ConsumerWidget {
  const NgoDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    // Live counts for tab badges
    final needsAsync = ref.watch(verifiedNeedsStreamProvider);
    final unassignedCount = needsAsync.valueOrNull
            ?.where((n) => n.status == 'open')
            .length ??
        0;
    final inProgressCount = needsAsync.valueOrNull
            ?.where((n) => n.status == 'dispatched')
            .length ??
        0;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        appBar: AppBar(
          backgroundColor: scheme.surface,
          elevation: 0,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.crisis_alert_rounded,
                    size: 20, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NGO Radar',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    'Command Dashboard',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Sign out',
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
                ref.read(authProvider.notifier).reset();
              },
            ),
          ],
        ),
        body: ResponsiveContainer(
          child: Column(
            children: [
              // ── Search bar + category chips ──────────────────
              Container(
                color: scheme.surface,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: const SearchBarWidget(),
              ),

              // ── Map placeholder ──────────────────────────────
              Container(
                height: 140,
                color: scheme.surfaceContainerLowest,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: const NgoMapTab(),
              ),

              // ── Tab bar ──────────────────────────────────────
              Container(
                color: scheme.surface,
                child: TabBar(
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Unassigned'),
                          if (unassignedCount > 0) ...[
                            const SizedBox(width: 6),
                            _Badge(count: unassignedCount),
                          ],
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('In Progress'),
                          if (inProgressCount > 0) ...[
                            const SizedBox(width: 6),
                            _Badge(
                                count: inProgressCount,
                                color: const Color(0xFFFF9500)),
                          ],
                        ],
                      ),
                    ),
                  ],
                  labelStyle:
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  unselectedLabelStyle:
                      const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
                  indicatorWeight: 3,
                ),
              ),

              // ── Tab content ──────────────────────────────────
              const Expanded(
                child: TabBarView(
                  children: [
                    NeedsListTab(status: 'open'),
                    NeedsListTab(status: 'dispatched'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Count badge widget ─────────────────────────────────────

class _Badge extends StatelessWidget {
  final int count;
  final Color? color;
  const _Badge({required this.count, this.color});

  @override
  Widget build(BuildContext context) {
    final bg = color ?? Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
