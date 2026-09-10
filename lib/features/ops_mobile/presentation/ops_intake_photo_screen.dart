import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// import 'package:image_picker/image_picker.dart'; // Will add later if needed

class OpsIntakePhotoScreen extends ConsumerStatefulWidget {
  final String jobId;
  const OpsIntakePhotoScreen({super.key, required this.jobId});

  @override
  ConsumerState<OpsIntakePhotoScreen> createState() => _OpsIntakePhotoScreenState();
}

class _OpsIntakePhotoScreenState extends ConsumerState<OpsIntakePhotoScreen> {
  final List<String> _photos = [];
  bool _isUploading = false;

  void _takePhoto() async {
    // Stub for image picker
    setState(() {
      _photos.add('photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
    });
  }

  void _completeIntake() async {
    setState(() => _isUploading = true);
    // TODO: Upload photos to R2 and update repair_jobs status to '5_admitted'
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle Intake Completed!')));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pickup Intake'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Document Vehicle Condition',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please take photos of all 4 sides of the vehicle and any existing damage before accepting the keys.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _photos.isEmpty
                  ? Center(
                      child: Text('No photos added yet', style: TextStyle(color: Colors.grey.shade400)),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _photos.length,
                      itemBuilder: (context, index) {
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Icon(Icons.image, size: 48, color: Colors.grey),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Add Photo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _photos.isEmpty || _isUploading ? null : _completeIntake,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFd10721),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isUploading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Complete Intake & Admit Vehicle'),
            ),
          ],
        ),
      ),
    );
  }
}
