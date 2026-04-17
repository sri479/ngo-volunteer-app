import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppAuthState {
  final bool isLoading;
  final String? error;
  final bool success;
  final String? userRole;

  AppAuthState({
    this.isLoading = false,
    this.error,
    this.success = false,
    this.userRole,
  });

  AppAuthState copyWith({
    bool? isLoading,
    String? error,
    bool? success,
    String? userRole,
  }) {
    return AppAuthState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      success: success ?? this.success,
      userRole: userRole ?? this.userRole,
    );
  }
}

class AuthNotifier extends StateNotifier<AppAuthState> {
  AuthNotifier() : super(AppAuthState());

  final supabase = Supabase.instance.client;

  void reset() {
    state = AppAuthState();
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null, success: false, userRole: null);

    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user != null) {
        // Query the profile table for their role
        final profile = await supabase
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .single();

        final role = profile['role'] as String?;
        
        state = state.copyWith(isLoading: false, success: true, userRole: role);
      } else {
        state = state.copyWith(isLoading: false, error: 'Sign in failed.');
      }
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
    required String phone,
  }) async {
    state = state.copyWith(isLoading: true, error: null, success: false, userRole: null);

    try {
      // 1. Call Supabase auth.signUp()
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': name,
        },
      );

      final user = response.user;
      if (user != null) {
        // 2. Insert/Upsert their profile data into the profiles table
        await supabase.from('profiles').upsert({
          'id': user.id,
          'email': email,
          'full_name': name,
          'role': role,
          'phone': phone,
        });

        state = state.copyWith(isLoading: false, success: true, userRole: role);
      } else {
        state = state.copyWith(
            isLoading: false, error: 'Sign up failed. Please try again.');
      }
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AppAuthState>((ref) {
  return AuthNotifier();
});
