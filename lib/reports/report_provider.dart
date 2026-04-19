import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

// ── Nominatim geocoding ─────────────────────────────────────
/// Converts a human-readable address into a PostGIS POINT string.
/// Returns null if Nominatim cannot resolve the address.
Future<String?> geocodeAddressToPoint(String address) async {
  try {
    final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
        .replace(queryParameters: {
      'q': address.trim(),
      'format': 'json',
      'limit': '1',
    });
    final response = await http.get(uri, headers: {
      'User-Agent': 'ReliefLink/1.0',
    }).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as List<dynamic>;
    if (data.isEmpty) return null;

    final lat = double.tryParse(data[0]['lat'] as String? ?? '');
    final lon = double.tryParse(data[0]['lon'] as String? ?? '');
    if (lat == null || lon == null) return null;

    return 'POINT($lon $lat)';
  } catch (_) {
    return null;
  }
}


class ReportState {
  final bool isLoading;
  final String? error;
  final bool success;

  ReportState({
    this.isLoading = false,
    this.error,
    this.success = false,
  });

  ReportState copyWith({
    bool? isLoading,
    String? error,
    bool? success,
  }) {
    return ReportState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      success: success ?? this.success,
    );
  }
}

class ReportNotifier extends StateNotifier<ReportState> {
  ReportNotifier() : super(ReportState());

  final supabase = Supabase.instance.client;

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    return await Geolocator.getCurrentPosition();
  }

  /// Uploads [imageFile] to Supabase Storage bucket `report-images`
  /// and returns the public URL.
  Future<String> _uploadImage(XFile imageFile) async {
    final userId = supabase.auth.currentUser?.id ?? 'anon';
    final ext = imageFile.name.split('.').last.toLowerCase();
    final fileName = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    if (kIsWeb) {
      // On web, upload as bytes
      final Uint8List bytes = await imageFile.readAsBytes();
      await supabase.storage.from('report-images').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: _mimeFromExt(ext)),
          );
    } else {
      // On mobile/desktop, upload using the file path
      await supabase.storage.from('report-images').upload(
            fileName,
            File(imageFile.path),
            fileOptions: FileOptions(contentType: _mimeFromExt(ext)),
          );
    }

    return supabase.storage.from('report-images').getPublicUrl(fileName);
  }

  String _mimeFromExt(String ext) {
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'heic': 'image/heic',
    };
    return map[ext] ?? 'image/jpeg';
  }

  Future<void> submitReport({
    required String description,
    required bool useGps,
    required String? manualAddress,
    XFile? imageFile,
    String? geocodedGpsCoords, // pre-computed POINT string from Nominatim
  }) async {
    state = state.copyWith(isLoading: true, error: null, success: false);

    try {
      // ── 1. Upload image (if any) ──────────────────────────────
      String? imageUrl;
      if (imageFile != null) {
        imageUrl = await _uploadImage(imageFile);
      }

      // ── 2. Resolve GPS coords (if needed) ────────────────────
      String? gpsCoordsStr;
      if (useGps) {
        final position = await _determinePosition();
        gpsCoordsStr = 'POINT(${position.longitude} ${position.latitude})';
      }

      // ── 3. Fetch reporter name ────────────────────────────────
      final user = supabase.auth.currentUser;
      String? reporterName;
      if (user != null) {
        reporterName = user.userMetadata?['full_name'] as String?;
        if (reporterName == null || reporterName.isEmpty) {
          try {
            final profile = await supabase
                .from('profiles')
                .select('full_name')
                .eq('id', user.id)
                .single();
            reporterName = profile['full_name'] as String?;
          } catch (_) {}
        }
      }

      // ── 4. Build insert payload ───────────────────────────────
      // raw_description is nullable — only include if provided
      final trimmedDesc = description.trim();
      final Map<String, dynamic> reportData = {
        'loc_method': useGps ? 'gps' : 'manual',
        'is_processed': false,
      };

      if (trimmedDesc.isNotEmpty) {
        reportData['raw_description'] = trimmedDesc;
      }

      if (imageUrl != null) {
        reportData['image_url'] = imageUrl;
      }

      if (reporterName != null && reporterName.isNotEmpty) {
        reportData['reporter_name'] = reporterName;
      }

      if (useGps && gpsCoordsStr != null) {
        reportData['gps_coords'] = gpsCoordsStr;
      } else {
        // Always store the human-readable label
        if (manualAddress != null && manualAddress.isNotEmpty) {
          reportData['manual_address'] = manualAddress;
        }
        // If we have a geocoded point, store it too so the map can pin it
        if (geocodedGpsCoords != null) {
          reportData['gps_coords'] = geocodedGpsCoords;
        }
      }

      // ── 5. Insert report ──────────────────────────────────────
      await supabase.from('field_reports').insert(reportData);

      state = state.copyWith(isLoading: false, success: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final reportProvider =
    StateNotifierProvider<ReportNotifier, ReportState>((ref) {
  return ReportNotifier();
});
