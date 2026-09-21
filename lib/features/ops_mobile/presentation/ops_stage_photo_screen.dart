import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/image_compressor.dart';
import '../ops_access.dart';

// ─── Stage metadata ───────────────────────────────────────────────────────────

/// Canonical definition of every ops repair stage.
/// [stageKey]      — DB key, used in job_milestones.stage_key and notifications.
/// [label]         — Human-readable stage name.
/// [instruction]   — Shown to the operator inside the photo screen.
/// [minPhotos]     — Minimum photos required before submission.
/// [advancesStatus]— If non-null, calls advance_job_status after milestone insert.
/// [allowedRoles]  — Which roles can complete this stage.
class OpsStageDefinition {
  final String stageKey;
  final String label;
  final String instruction;
  final int minPhotos;
  final String? advancesStatus;
  final List<String> allowedRoles;
  const OpsStageDefinition({
    required this.stageKey,
    required this.label,
    required this.instruction,
    required this.minPhotos,
    this.advancesStatus,
    required this.allowedRoles,
  });
}

const kOpsStages = <OpsStageDefinition>[
  OpsStageDefinition(
    stageKey: 'vehicle_intake',
    label: 'Vehicle Intake',
    instruction:
        'Document all 4 sides of the vehicle plus any pre-existing damage before handing over the keys. '
        'Min 2 photos required.',
    minPhotos: 2,
    advancesStatus: '5_admitted',
    allowedRoles: ['partner_staff', 'partner_driver', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'disassembly',
    label: 'Disassembly',
    instruction:
        'Photograph each damaged panel after removal. Include before/after shots of the disassembled area.',
    minPhotos: 1,
    advancesStatus: '6_in_progress',
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'welding',
    label: 'Welding / Panel Beating',
    instruction:
        'Photograph the repaired structural panels after welding or panel beating. Show all weld points.',
    minPhotos: 1,
    advancesStatus: null, // Sub-stage within 6_in_progress; no status change
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'body_filler',
    label: 'Body Filler (Dempul)',
    instruction:
        'Photograph panels after body filler application. Capture coverage and surface smoothness.',
    minPhotos: 1,
    advancesStatus: null,
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'painting',
    label: 'Painting',
    instruction:
        'Photograph panels in the paint booth after base coat and clear coat application.',
    minPhotos: 1,
    advancesStatus: null,
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'polishing',
    label: 'Polishing & Detailing',
    instruction:
        'Photograph the finished polished panels. Include full-vehicle shot from each side.',
    minPhotos: 2,
    advancesStatus: null,
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'qc_finished',
    label: 'Quality Control',
    instruction:
        'QC sign-off photos. Photograph all repaired areas and complete vehicle — 4 sides minimum.',
    minPhotos: 2,
    advancesStatus: '7_finished',
    allowedRoles: ['partner_staff', 'partner_mechanic', 'master_admin'],
  ),
  OpsStageDefinition(
    stageKey: 'delivery',
    label: 'Delivery / Pickup',
    instruction:
        'Photograph the vehicle being handed to the customer. Include handover proof with customer present if possible.',
    minPhotos: 1,
    advancesStatus: '9_done',
    allowedRoles: ['partner_driver', 'partner_mechanic', 'master_admin'],
  ),
];

OpsStageDefinition? stageByKey(String key) {
  try {
    return kOpsStages.firstWhere((s) => s.stageKey == key);
  } catch (_) {
    return null;
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

/// Generic per-stage photo capture screen.
/// Used for every repair milestone stage. Handles:
///   1. ImagePicker → compression → Supabase Storage upload
///   2. Milestone record upsert via appropriate RPC or direct insert
///   3. Notification dispatch via send-notification edge function
///   4. Optional job status advancement
class OpsStagePhotoScreen extends ConsumerStatefulWidget {
  final String jobId;
  final String customerId; // needed for notification dispatch
  final String stageKey;

  const OpsStagePhotoScreen({
    super.key,
    required this.jobId,
    required this.customerId,
    required this.stageKey,
  });

  @override
  ConsumerState<OpsStagePhotoScreen> createState() => _OpsStagePhotoScreenState();
}

class _OpsStagePhotoScreenState extends ConsumerState<OpsStagePhotoScreen> {
  final _picker = ImagePicker();
  final _sb = Supabase.instance.client;

  // Each entry is the compressed bytes + original filename
  final List<({Uint8List bytes, String name})> _photos = [];
  bool _isSubmitting = false;
  String? _errorMessage;
  OpsStageDefinition? _stage;

  @override
  void initState() {
    super.initState();
    _stage = stageByKey(widget.stageKey);
  }

  // ── Role guard ─────────────────────────────────────────────────────────────
  bool _callerIsAllowed() {
    final role = _sb.auth.currentUser?.appMetadata['role'] as String?;
    // In all_access every ops operator may complete any stage; in original_role
    // the stage's own role list decides (the pre-existing behaviour).
    final mode = ref.read(opsViewModeProvider).valueOrNull ?? OpsViewMode.allAccess;
    return opsRoleMayActOnStage(mode, role, _stage?.allowedRoles ?? const []);
  }

  // ── Pick from camera ───────────────────────────────────────────────────────
  Future<void> _addPhotoFromCamera() async {
    if (_photos.length >= 8) {
      _showError('Maximum 8 photos per stage.');
      return;
    }
    try {
      final raw = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90, // Pre-compress before our pipeline
        maxWidth: 2560,
        maxHeight: 1920,
      );
      if (raw == null) return;
      await _compressAndAdd(raw);
    } catch (e) {
      debugPrint('[StagePhoto] Camera error: $e');
      _showError('Camera access failed. Check permissions.');
    }
  }

  // ── Pick from gallery ──────────────────────────────────────────────────────
  Future<void> _addPhotoFromGallery() async {
    if (_photos.length >= 8) {
      _showError('Maximum 8 photos per stage.');
      return;
    }
    try {
      final raw = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 2560,
        maxHeight: 1920,
      );
      if (raw == null) return;
      await _compressAndAdd(raw);
    } catch (e) {
      debugPrint('[StagePhoto] Gallery error: $e');
      _showError('Could not access gallery.');
    }
  }

  Future<void> _compressAndAdd(XFile raw) async {
    setState(() => _errorMessage = null);
    try {
      final compressed = await ImageCompressor.compressImage(raw);
      setState(() {
        _photos.add((
          bytes: compressed,
          name: '${DateTime.now().millisecondsSinceEpoch}.jpg',
        ));
      });
    } catch (e) {
      debugPrint('[StagePhoto] Compression error: $e');
      _showError('Image compression failed.');
    }
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  void _showError(String msg) {
    setState(() => _errorMessage = msg);
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final stage = _stage;
    if (stage == null) return;

    if (!_callerIsAllowed()) {
      _showError('You do not have permission to complete this stage.');
      return;
    }

    if (_photos.length < stage.minPhotos) {
      _showError('Please add at least ${stage.minPhotos} photo(s) before submitting.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      // 1. Upload photos to Supabase Storage
      final partnerId = _sb.auth.currentUser?.appMetadata['partner_id'] as String? ?? 'unknown';
      final fileKeys = <String>[];

      for (final photo in _photos) {
        final fileKey =
            'ops/$partnerId/${widget.jobId}/${stage.stageKey}/${photo.name}';
        await _sb.storage.from('revive-photos').uploadBinary(
              fileKey,
              photo.bytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
            );
        fileKeys.add(fileKey);
      }

      // 2. Call the appropriate RPC based on stage
      dynamic rpcResult;

      if (stage.stageKey == 'vehicle_intake') {
        rpcResult = await _sb.rpc('ops_complete_intake', params: {
          'p_job_id': widget.jobId,
          'p_file_keys': fileKeys,
        });
      } else if (stage.stageKey == 'delivery') {
        rpcResult = await _sb.rpc('ops_complete_delivery', params: {
          'p_job_id': widget.jobId,
          'p_file_keys': fileKeys,
        });
      } else {
        // Mid-repair stages: upsert milestone + optional status advance
        final milestoneResult = await _sb.from('job_milestones').upsert({
          'job_id': widget.jobId,
          'milestone_name': stage.label,
          'stage_key': stage.stageKey,
          'status': 'completed',
          'completed_by': _sb.auth.currentUser?.id,
          'completed_at': DateTime.now().toIso8601String(),
        }, onConflict: 'job_id,stage_key').select('id').single();

        final milestoneId = milestoneResult['id'] as String;

        // Insert photo records
        for (final fk in fileKeys) {
          await _sb.from('job_milestone_photos').insert({
            'milestone_id': milestoneId,
            'job_id': widget.jobId,
            'uploaded_by': _sb.auth.currentUser?.id,
            'file_key': fk,
          });
        }

        // Advance status if this stage triggers one
        if (stage.advancesStatus != null) {
          await _sb.rpc('advance_job_status', params: {
            'p_job_id': widget.jobId,
            'p_new_status': stage.advancesStatus,
          });
        }

        rpcResult = {'success': true};
      }

      // 3. Parse RPC success
      final Map<String, dynamic> response = rpcResult is Map<String, dynamic>
          ? rpcResult
          : {'success': true};

      if (response['success'] == false) {
        _showError(response['error']?.toString() ?? 'Operation failed.');
        setState(() => _isSubmitting = false);
        return;
      }

      // 4. Dispatch milestone notification (fire-and-forget)
      _dispatchMilestoneNotification(stage.stageKey);

      if (!mounted) return;

      // 5. Success feedback + return
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${stage.label} completed with ${fileKeys.length} photo(s). Customer notified.'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 3),
      ));
      context.pop(true); // Pop with `true` to signal refresh to caller
    } catch (e) {
      debugPrint('[StagePhoto] Submit error: $e');
      _showError('Submission failed: ${e.toString().replaceAll('PostgrestException', '').trim()}');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _dispatchMilestoneNotification(String stageKey) async {
    try {
      final session = _sb.auth.currentSession;
      if (session == null) return;

      final body = {
        'job_id': widget.jobId,
        'customer_id': widget.customerId,
        'milestone_stage_key': stageKey,
      };

      // supabase_flutter's functions.invoke sends the user's JWT automatically.
      // The edge function accepts the user JWT for milestone notification calls.
      final res = await _sb.functions.invoke(
        'send-notification',
        body: body,
      );
      debugPrint('[StagePhoto] Notification result: ${res.status} ${res.data}');
    } catch (e) {
      // Non-fatal: log but don't surface to user
      debugPrint('[StagePhoto] Notification dispatch error (non-fatal): $e');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    final cs = Theme.of(context).colorScheme;

    if (stage == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Unknown Stage')),
        body: const Center(child: Text('Invalid stage key.')),
      );
    }

    final minMet = _photos.length >= stage.minPhotos;

    return Scaffold(
      appBar: AppBar(
        title: Text(stage.label),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ── Instruction banner ──────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: cs.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.camera_alt_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Min ${stage.minPhotos} photo${stage.minPhotos > 1 ? 's' : ''} required',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    '${_photos.length}/8',
                    style: TextStyle(
                      fontSize: 13,
                      color: _photos.length >= 8 ? Colors.orange : cs.onSurfaceVariant,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  stage.instruction,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // ── Error message ───────────────────────────────────────────────────
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.red.shade50,
              child: Row(children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                  ),
                ),
              ]),
            ),

          // ── Photo grid ─────────────────────────────────────────────────────
          Expanded(
            child: _photos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'No photos added yet',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _photos.length,
                    itemBuilder: (context, index) {
                      final photo = _photos[index];
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(photo.bytes, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _removePhoto(index),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(Icons.close, color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),

          // ── Add photo buttons ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSubmitting || _photos.length >= 8
                        ? null
                        : _addPhotoFromCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSubmitting || _photos.length >= 8
                        ? null
                        : _addPhotoFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Status advance hint ─────────────────────────────────────────────
          if (stage.advancesStatus != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Completing this stage will advance job status to "${stage.advancesStatus}".',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
              ]),
            ),

          // ── Submit button ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (!minMet || _isSubmitting) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD10721),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: _isSubmitting
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Uploading & Notifying Customer…'),
                        ],
                      )
                    : Text(
                        minMet
                            ? 'Submit ${stage.label} (${_photos.length} photo${_photos.length != 1 ? 's' : ''})'
                            : 'Add ${stage.minPhotos - _photos.length} more photo${stage.minPhotos - _photos.length != 1 ? 's' : ''} to continue',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
