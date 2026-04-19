import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'ngo_providers.dart';
import 'need_bottom_sheet.dart';

class NgoMapTab extends ConsumerStatefulWidget {
  const NgoMapTab({super.key});

  @override
  ConsumerState<NgoMapTab> createState() => _NgoMapTabState();
}

class _NgoMapTabState extends ConsumerState<NgoMapTab> {
  final MapController _mapController = MapController();
  bool _hasFitBounds = false;

  @override
  Widget build(BuildContext context) {
    final needsAsync = ref.watch(verifiedNeedsStreamProvider);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: needsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading map: $e')),
        data: (needs) {
          final markers = needs
              .where((n) => n.latitude != null && n.longitude != null)
              .map((n) => Marker(
                    point: LatLng(n.latitude!, n.longitude!),
                    width: 24,
                    height: 24,
                    child: GestureDetector(
                      onTap: () => showNeedBottomSheet(context, n),
                      child: _PriorityMarker(priority: n.priorityScore),
                    ),
                  ))
              .toList();

          // Fit bounds once on first load if markers exist
          if (!_hasFitBounds && markers.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                final bounds = LatLngBounds.fromPoints(
                    markers.map((m) => m.point).toList());
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(50),
                    maxZoom: 15,
                  ),
                );
                setState(() => _hasFitBounds = true);
              }
            });
          }

          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(20.5937, 78.9629), // Center India
              initialZoom: 5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.volunteer_app',
              ),
              MarkerLayer(markers: markers),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    '© OpenStreetMap contributors',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PriorityMarker extends StatelessWidget {
  final int priority;
  const _PriorityMarker({required this.priority});

  Color _getColor() {
    if (priority >= 8) return const Color(0xFFFF3B30); // Red
    if (priority >= 5) return const Color(0xFFFF9500); // Orange
    return const Color(0xFF34C759); // Green
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}
