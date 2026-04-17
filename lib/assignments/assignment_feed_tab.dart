import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AssignmentFeedTab extends StatefulWidget {
  const AssignmentFeedTab({super.key});

  @override
  State<AssignmentFeedTab> createState() => _AssignmentFeedTabState();
}

class _AssignmentFeedTabState extends State<AssignmentFeedTab> {
  final _supabase = Supabase.instance.client;
  late final Stream<List<Map<String, dynamic>>> _assignmentsStream;

  StreamController<List<Map<String, dynamic>>>? _controller;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      _controller = StreamController<List<Map<String, dynamic>>>();
      _fetchData(userId);

      _channel = _supabase
          .channel('volunteer_feed_\$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'assignments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'volunteer_id',
              value: userId,
            ),
            callback: (_) => _fetchData(userId),
          )
          .subscribe();
      
      _assignmentsStream = _controller!.stream;
    } else {
      _assignmentsStream = const Stream.empty();
    }
  }

  Future<void> _fetchData(String userId) async {
    try {
      final data = await _supabase
          .from('assignments')
          .select('*, verified_needs(category, ai_summary)')
          .eq('volunteer_id', userId)
          .order('created_at', ascending: false);
      if (_controller != null && !_controller!.isClosed) {
        _controller!.add(List<Map<String, dynamic>>.from(data));
      }
    } catch (e) {
      if (_controller != null && !_controller!.isClosed) {
        _controller!.addError(e);
      }
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _controller?.close();
    super.dispose();
  }

  Future<void> _updateStatus(String assignmentId, String newStatus, String needId) async {
    try {
      await _supabase.from('assignments').update({'status': newStatus}).eq('id', assignmentId);
      
      // If completed, also mark the need as resolved
      if (newStatus == 'completed') {
        await _supabase.from('verified_needs').update({'status': 'resolved'}).eq('id', needId);
      } else if (newStatus == 'cancelled') {
        // If rejected, mark the need back to open so the NGO can assign it again
        await _supabase.from('verified_needs').update({'status': 'open'}).eq('id', needId);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mission marked as \$newStatus')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: \$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _assignmentsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final assignments = snapshot.data;
        
        if (assignments == null || assignments.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                const SizedBox(height: 16),
                Text('No Active Missions', style: Theme.of(context).textTheme.titleLarge),
                const Text('Stand by for new assignments.'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: assignments.length,
          itemBuilder: (context, index) {
            final assignment = assignments[index];
            final vn = assignment['verified_needs'] as Map?;
            final category = vn?['category']?.toString() ?? 'Mission Assignment';
            final status = assignment['status']?.toString() ?? 'pending';
            final summary = vn?['ai_summary']?.toString() ?? 'No description provided';
            
            return Card(
              margin: const EdgeInsets.only(bottom: 16.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            category,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Chip(
                          label: Text(status),
                          backgroundColor: status.toLowerCase() == 'active' ? Colors.blue.shade100 : Colors.grey.shade200,
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(summary),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (status.toLowerCase() == 'pending') ...[
                          OutlinedButton(
                            onPressed: () => _updateStatus(assignment['id'], 'cancelled', assignment['need_id']),
                            child: const Text('Reject', style: TextStyle(color: Colors.red)),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => _updateStatus(assignment['id'], 'accepted', assignment['need_id']),
                            child: const Text('Accept Mission'),
                          ),
                        ] else if (status.toLowerCase() == 'accepted') ...[
                          FilledButton.icon(
                            onPressed: () => _updateStatus(assignment['id'], 'completed', assignment['need_id']),
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Mark Completed'),
                            style: FilledButton.styleFrom(backgroundColor: Colors.green),
                          ),
                        ] else if (status.toLowerCase() == 'completed') ...[
                          const Chip(
                            avatar: Icon(Icons.verified, color: Colors.green, size: 18),
                            label: Text('Mission Accomplished'),
                          )
                        ],
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
