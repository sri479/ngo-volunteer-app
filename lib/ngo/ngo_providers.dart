import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────

class NeedWithReport {
  final String id;
  final String? reportId;
  final String category;
  final int priorityScore;
  final String aiSummary;
  final List<String> requiredSkills;
  final String status; // open | dispatched | resolved
  final DateTime? reportCreatedAt;
  final double? similarity; // populated by search results

  NeedWithReport({
    required this.id,
    this.reportId,
    required this.category,
    required this.priorityScore,
    required this.aiSummary,
    required this.requiredSkills,
    required this.status,
    this.reportCreatedAt,
    this.similarity,
  });

  factory NeedWithReport.fromMap(Map<String, dynamic> m) {
    // Handle nested field_reports join or flat created_at
    DateTime? createdAt;
    final fr = m['field_reports'];
    if (fr is Map) {
      final raw = fr['created_at'];
      if (raw is String) createdAt = DateTime.tryParse(raw)?.toLocal();
    } else if (m['created_at'] is String) {
      createdAt = DateTime.tryParse(m['created_at'] as String)?.toLocal();
    }

    return NeedWithReport(
      id: m['id'] as String? ?? '',
      reportId: m['report_id'] as String?,
      category: m['category'] as String? ?? 'Other',
      priorityScore: (m['priority_score'] as num?)?.toInt() ?? 5,
      aiSummary: m['ai_summary'] as String? ?? '',
      requiredSkills: (m['required_skills'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      status: m['status'] as String? ?? 'open',
      reportCreatedAt: createdAt,
      similarity: (m['similarity'] as num?)?.toDouble(),
    );
  }
}

class MatchedVolunteer {
  final String id;
  final String fullName;
  final bool isAvailable;
  final List<String> skills;
  final double distMeters;

  MatchedVolunteer({
    required this.id,
    required this.fullName,
    required this.isAvailable,
    required this.skills,
    required this.distMeters,
  });

  factory MatchedVolunteer.fromMap(Map<String, dynamic> m) {
    return MatchedVolunteer(
      id: m['id'] as String? ?? '',
      fullName: m['full_name'] as String? ?? 'Unknown Volunteer',
      isAvailable: m['is_available'] as bool? ?? false,
      skills: (m['skills'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      distMeters:
          (m['dist_meters'] as num?)?.toDouble() ?? double.infinity,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// REALTIME STREAM PROVIDERS
// ─────────────────────────────────────────────────────────────

/// Streams verified_needs joined with field_reports.created_at.
/// Refreshes on changes to either verified_needs OR assignments.
final verifiedNeedsStreamProvider =
    StreamProvider<List<NeedWithReport>>((ref) {
  final supabase = Supabase.instance.client;
  final controller =
      StreamController<List<NeedWithReport>>.broadcast();

  Future<void> fetch() async {
    try {
      final data = await supabase
          .from('verified_needs')
          .select(
              'id, category, priority_score, ai_summary, required_skills, status, report_id, field_reports(created_at)')
          .order('priority_score', ascending: false);
      if (!controller.isClosed) {
        controller.add(
          (data as List<dynamic>)
              .map((r) =>
                  NeedWithReport.fromMap(r as Map<String, dynamic>))
              .toList(),
        );
      }
    } catch (_) {
      // Silently retry on next realtime event
    }
  }

  fetch();

  final channel = supabase
      .channel('ngo-needs-realtime')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'verified_needs',
        callback: (_) => fetch(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'assignments',
        callback: (_) => fetch(),
      )
      .subscribe();

  ref.onDispose(() {
    supabase.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

/// Streams the raw assignments table for badge counts / status tracking.
final assignmentsStreamProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final supabase = Supabase.instance.client;
  final controller =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  Future<void> fetch() async {
    try {
      final data = await supabase
          .from('assignments')
          .select('*')
          .order('created_at', ascending: false);
      if (!controller.isClosed) {
        controller.add(List<Map<String, dynamic>>.from(data as List));
      }
    } catch (_) {}
  }

  fetch();

  final channel = supabase
      .channel('ngo-assignments-realtime')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'assignments',
        callback: (_) => fetch(),
      )
      .subscribe();

  ref.onDispose(() {
    supabase.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ─────────────────────────────────────────────────────────────
// FILTER & SEARCH STATE
// ─────────────────────────────────────────────────────────────

final searchQueryProvider = StateProvider<String>((ref) => '');
final categoryFilterProvider = StateProvider<String?>((ref) => null);

/// FutureProvider: calls search-needs edge function with debounced query.
/// autoDispose so it re-runs fresh after inactivity.
final searchResultsProvider =
    FutureProvider.autoDispose<List<NeedWithReport>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];

  final supabase = Supabase.instance.client;
  try {
    final response = await supabase.functions.invoke(
      'search-needs',
      body: {'query': query.trim(), 'threshold': 0.4, 'count': 20},
    );

    if (response.status != 200) {
      final data = response.data;
      final serverMessage = (data is Map && data.containsKey('message'))
          ? data['message']
          : data.toString();
      throw 'Search Service Error: $serverMessage';
    }

    final raw = response.data;
    if (raw is List) {
      return raw
          .map<NeedWithReport>(
              (r) => NeedWithReport.fromMap(r as Map<String, dynamic>))
          .toList();
    }
    return [];
  } on FunctionException catch (e) {
    throw 'Connection failed (${e.status}): ${e.details ?? e.reasonPhrase}';
  } catch (e) {
    rethrow;
  }
});

/// Combined provider:
/// - query non-empty → semantic search results (from edge function)
/// - query empty → realtime stream, optionally filtered by category
final displayedNeedsProvider =
    Provider<AsyncValue<List<NeedWithReport>>>((ref) {
  final query = ref.watch(searchQueryProvider);
  final category = ref.watch(categoryFilterProvider);

  final AsyncValue<List<NeedWithReport>> raw = query.trim().isNotEmpty
      ? ref.watch(searchResultsProvider)
      : ref.watch(verifiedNeedsStreamProvider);

  // Apply category filter (works for both search results and stream)
  if (category == null || category == 'All') return raw;
  return raw.whenData(
    (needs) => needs
        .where((n) => n.category.toLowerCase() == category.toLowerCase())
        .toList(),
  );
});

// ─────────────────────────────────────────────────────────────
// VOLUNTEER MATCH (calls match_volunteers_for_need RPC)
// ─────────────────────────────────────────────────────────────

final volunteerMatchProvider = FutureProvider.autoDispose
    .family<List<MatchedVolunteer>, String>((ref, needId) async {
  final supabase = Supabase.instance.client;
  final data = await supabase.rpc(
    'match_volunteers_for_need',
    params: {'p_need_id': needId},
  );
  return (data as List<dynamic>)
      .map((v) => MatchedVolunteer.fromMap(v as Map<String, dynamic>))
      .toList();
});

// ─────────────────────────────────────────────────────────────
// DISPATCH STATE
//
// ⚠️  REQUIRED SQL POLICY (run once in Supabase SQL editor):
// CREATE POLICY "NGO admins can update verified_needs status"
//   ON verified_needs FOR UPDATE
//   USING ((SELECT role FROM profiles WHERE id = auth.uid()) = 'ngo_admin');
// ─────────────────────────────────────────────────────────────

class DispatchState {
  final bool isLoading;
  final String? error;
  final bool success;

  DispatchState({
    this.isLoading = false,
    this.error,
    this.success = false,
  });

  DispatchState copyWith(
          {bool? isLoading, String? error, bool? success}) =>
      DispatchState(
        isLoading: isLoading ?? this.isLoading,
        error: error,
        success: success ?? this.success,
      );
}

class DispatchNotifier extends StateNotifier<DispatchState> {
  DispatchNotifier() : super(DispatchState());

  Future<void> dispatch({
    required String needId,
    required String volunteerId,
  }) async {
    state = state.copyWith(isLoading: true, error: null, success: false);
    try {
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) throw Exception('Not authenticated');

      // 1. Create assignment record
      await supabase.from('assignments').insert({
        'need_id': needId,
        'volunteer_id': volunteerId,
        'assigned_by': currentUser.id,
        'status': 'pending',
      });

      // 2. Mark need as dispatched
      await supabase
          .from('verified_needs')
          .update({'status': 'dispatched'}).eq('id', needId);

      state = state.copyWith(isLoading: false, success: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final dispatchProvider =
    StateNotifierProvider.autoDispose<DispatchNotifier, DispatchState>(
  (ref) => DispatchNotifier(),
);
