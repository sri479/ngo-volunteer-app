import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class VolunteerProfileTab extends ConsumerStatefulWidget {
  const VolunteerProfileTab({super.key});

  @override
  ConsumerState<VolunteerProfileTab> createState() => _VolunteerProfileTabState();
}

class _VolunteerProfileTabState extends ConsumerState<VolunteerProfileTab> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isAvailable = false;
  List<String> _selectedSkills = [];
  String _lastKnownLocation = 'Unknown';
  
  static const List<String> _coreSkills = [
    'Medical',
    'Search & Rescue',
    'Heavy Machinery',
    'Logistics',
    'Communications',
    'General Labor'
  ];
  final List<String> _availableSkills = List.from(_coreSkills);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('profiles')
          .select('is_available, skills, last_known_location')
          .eq('id', user.id)
          .single();

      setState(() {
        _isAvailable = data['is_available'] ?? false;
        
        final skillsData = data['skills'];
        if (skillsData != null) {
          _selectedSkills = List<String>.from(skillsData);
          for (final skill in _selectedSkills) {
            if (!_availableSkills.contains(skill)) {
              _availableSkills.add(skill);
            }
          }
        }
        
        _lastKnownLocation = data['last_known_location']?.toString() ?? 'Unknown';
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    }
  }

  Future<void> _updateProfile(Map<String, dynamic> updates) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('profiles').update(updates).eq('id', user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      }
    }
  }

  void _toggleSkill(String skill) {
    setState(() {
      if (_selectedSkills.contains(skill)) {
        _selectedSkills.remove(skill);
      } else {
        _selectedSkills.add(skill);
      }
    });
    _updateProfile({'skills': _selectedSkills});
  }

  void _toggleAvailability(bool value) {
    setState(() => _isAvailable = value);
    _updateProfile({'is_available': value});
  }

  Future<void> _updateLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    setState(() => _isLoading = true);

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled.';
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw 'Location permissions are permanently denied, we cannot request permissions.';
      }

      Position position = await Geolocator.getCurrentPosition();
      
      // We format as a simple geography PostGIS point if possible, otherwise string.
      // Adjust based on exact backend schema constraint. E.g., 'SRID=4326;POINT(lon lat)'
      final locationStr = 'POINT(${position.longitude} ${position.latitude})';

      setState(() => _lastKnownLocation = locationStr);
      await _updateProfile({'last_known_location': locationStr});
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _deleteCustomSkill(String skill) {
    setState(() {
      _availableSkills.remove(skill);
      if (_selectedSkills.contains(skill)) {
        _selectedSkills.remove(skill);
        _updateProfile({'skills': _selectedSkills});
      }
    });
  }

  Future<void> _showAddCustomSkillDialog() async {
    final controller = TextEditingController();
    final customSkill = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Custom Skill'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter skill name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (customSkill != null && customSkill.isNotEmpty) {
      if (!_availableSkills.contains(customSkill)) {
        setState(() {
          _availableSkills.add(customSkill);
          _selectedSkills.add(customSkill);
        });
        _updateProfile({'skills': _selectedSkills});
      } else if (!_selectedSkills.contains(customSkill)) {
        _toggleSkill(customSkill);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Readiness Profile',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          
          Card(
            child: SwitchListTile(
              title: const Text('Currently Available'),
              subtitle: const Text('Toggle to show if you can take missions right now.'),
              value: _isAvailable,
              onChanged: _toggleAvailability,
            ),
          ),
          const SizedBox(height: 24),

          Text('My Skills', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              ..._availableSkills.map((skill) {
                final isSelected = _selectedSkills.contains(skill);
                final isCustom = !_coreSkills.contains(skill);
                return FilterChip(
                  label: Text(skill),
                  selected: isSelected,
                  onSelected: (_) => _toggleSkill(skill),
                  onDeleted: isCustom ? () => _deleteCustomSkill(skill) : null,
                );
              }),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Add Custom'),
                onPressed: _showAddCustomSkillDialog,
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          Text('Current Location Tracking', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Last Location: $_lastKnownLocation'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _updateLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Update Last Location'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
