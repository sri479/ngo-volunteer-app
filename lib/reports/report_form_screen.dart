import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'report_provider.dart';

class ReportFormScreen extends ConsumerStatefulWidget {
  const ReportFormScreen({super.key});

  @override
  ConsumerState<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends ConsumerState<ReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  bool _useGps = true;
  final ImagePicker _picker = ImagePicker();

  // Store XFile for cross-platform support (web + mobile)
  XFile? _pickedXFile;

  @override
  void dispose() {
    _descriptionController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() {
          _pickedXFile = pickedFile;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Capture Live Image'),
                subtitle: kIsWeb
                    ? const Text('Camera not available on web', style: TextStyle(color: Colors.orange))
                    : null,
                onTap: kIsWeb
                    ? () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Camera capture is only available on mobile devices.'),
                          ),
                        );
                      }
                    : () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.camera);
                      },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Upload from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds the preview widget cross-platform:
  /// - Web: reads bytes and uses Image.memory
  /// - Mobile/Desktop: uses Image.file
  Widget _buildImagePreview() {
    if (_pickedXFile == null) return const SizedBox.shrink();

    return Column(
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: kIsWeb
                  ? FutureBuilder<Uint8List>(
                      future: _pickedXFile!.readAsBytes(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Image.memory(
                            snapshot.data!,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          );
                        }
                        return const SizedBox(
                          height: 200,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                    )
                  : Image.file(
                      File(_pickedXFile!.path),
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle, color: Colors.red),
              onPressed: () {
                setState(() {
                  _pickedXFile = null;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _submit() {
    // Top-level guard: at least one of description or photo must be present
    final hasDescription = _descriptionController.text.trim().length >= 10;
    final hasPhoto = _pickedXFile != null;
    if (!hasDescription && !hasPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a description or attach a photo before submitting.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      if (!_useGps && _addressController.text.trim().length <= 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid manual address (min 4 chars).'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      ref.read(reportProvider.notifier).submitReport(
            description: _descriptionController.text.trim(),
            useGps: _useGps,
            manualAddress: _useGps ? null : _addressController.text.trim(),
            imageFile: _pickedXFile,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ReportState>(reportProvider, (previous, next) {
      if (next.error != null && (previous == null || previous.error != next.error)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!), backgroundColor: Colors.red),
        );
      } else if (next.success && (previous == null || !previous.success)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _descriptionController.clear();
        _addressController.clear();
        setState(() {
          _pickedXFile = null;
        });
      }
    });

    final reportState = ref.watch(reportProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Disaster / Need'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Field Report',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your report helps coordinate response efforts. Be descriptive.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: 'Description of the situation',
                      hintText: _pickedXFile != null
                          ? 'Optional — you have a photo attached'
                          : 'Describe what you see (required if no photo)',
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 5,
                    validator: (value) {
                      final hasText = value != null && value.trim().length >= 10;
                      final hasPhoto = _pickedXFile != null;
                      // If no photo, description must have at least 10 chars
                      if (!hasPhoto && !hasText) {
                        return 'Add a description (min 10 chars) or attach a photo';
                      }
                      // If there IS a photo but the user started typing, enforce min length
                      if (!hasPhoto && value != null && value.trim().isNotEmpty && value.trim().length < 10) {
                        return 'Description must be at least 10 characters long';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Location Settings',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          SwitchListTile(
                            title: const Text('Use my current GPS Location'),
                            subtitle: const Text('Fastest and most accurate option'),
                            value: _useGps,
                            onChanged: (val) {
                              setState(() {
                                _useGps = val;
                              });
                            },
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (!_useGps) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _addressController,
                              decoration: const InputDecoration(
                                labelText: 'Manual Address',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.location_on),
                              ),
                              validator: (value) {
                                if (!_useGps &&
                                    (value == null || value.trim().length <= 3)) {
                                  return 'Address is required and must be valid';
                                }
                                return null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Image preview (cross-platform)
                  _buildImagePreview(),
                  ElevatedButton.icon(
                    onPressed: _showImageSourceDialog,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(_pickedXFile == null ? 'Attach Photo' : 'Change Photo'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: reportState.isLoading ? null : _submit,
                      child: reportState.isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Submit Report',
                              style: TextStyle(fontSize: 18),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
