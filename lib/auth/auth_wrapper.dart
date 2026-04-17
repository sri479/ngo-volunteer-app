import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';
import 'role_selection_screen.dart';
import 'ngo_dashboard_screen.dart';
import '../dashboard/volunteer_dashboard_screen.dart';

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final supabase = Supabase.instance.client;

    // 1. If we are currently loading an auth action (sign in/up), show a loader
    if (authState.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 2. Listen to internal state first (for immediate transitions)
    if (authState.success && authState.userRole != null) {
      if (authState.userRole == 'ngo_admin') {
        return const NgoDashboardScreen();
      } else if (authState.userRole == 'volunteer') {
        return const VolunteerDashboardScreen();
      }
    }

    // 3. Fallback: Check deep session state (for app startup)
    return StreamBuilder<AppAuthState?>(
      stream: _getSessionFlow(ref),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final state = snapshot.data;
        if (state != null && state.success && state.userRole != null) {
          if (state.userRole == 'ngo_admin') {
            return const NgoDashboardScreen();
          } else if (state.userRole == 'volunteer') {
            return const VolunteerDashboardScreen();
          }
        }

        // Default to RoleSelection if no user or unknown role
        return const RoleSelectionScreen();
      },
    );
  }

  Stream<AppAuthState?> _getSessionFlow(WidgetRef ref) async* {
    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;
    
    if (session == null) {
      yield null;
      return;
    }

    try {
      final user = session.user;
      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();
      
      final role = profile['role'] as String?;
      yield AppAuthState(success: true, userRole: role);
    } catch (e) {
      yield null;
    }
  }
}
