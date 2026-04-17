import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_provider.dart';
import '../reports/report_form_screen.dart';
import '../profile/volunteer_profile_tab.dart';
import '../assignments/assignment_feed_tab.dart';
import '../shared/responsive_container.dart';

class VolunteerDashboardScreen extends ConsumerStatefulWidget {
  const VolunteerDashboardScreen({super.key});

  @override
  ConsumerState<VolunteerDashboardScreen> createState() => _VolunteerDashboardScreenState();
}

class _VolunteerDashboardScreenState extends ConsumerState<VolunteerDashboardScreen> {
  int _currentIndex = 1; // Default to Report (Sensor) Tab
  RealtimeChannel? _assignmentChannel;

  @override
  void initState() {
    super.initState();
    _setupRealtime();
  }

  void _setupRealtime() {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _assignmentChannel = supabase
        .channel('volunteer_assignments_\$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'assignments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'volunteer_id',
            value: userId,
          ),
          callback: (payload) {
            _showNewMissionPopup();
          },
        )
        .subscribe();
  }

  void _showNewMissionPopup() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🚨 New Mission Assigned!'),
        content: const Text('An NGO Admin has requested your help for an emergency. Check your Missions tab now.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _currentIndex = 0; // Switching to Missions tab
              });
            },
            child: const Text('View Mission'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _assignmentChannel?.unsubscribe();
    super.dispose();
  }

  final List<Widget> _tabs = [
    const AssignmentFeedTab(),     // 0: Feed
    const ReportFormScreen(),      // 1: Sensor (Form)
    const VolunteerProfileTab(),   // 2: Profile/Skills
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Volunteer Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              ref.read(authProvider.notifier).reset();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ResponsiveContainer(
          child: IndexedStack(
            index: _currentIndex,
            children: _tabs,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Missions',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_a_photo_outlined),
            selectedIcon: Icon(Icons.add_a_photo),
            label: 'Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
