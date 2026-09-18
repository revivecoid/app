/// ops_intake_photo_screen.dart
///
/// Vehicle intake — thin redirect to OpsStagePhotoScreen with stageKey='vehicle_intake'.
/// Kept as a named file so the existing route /ops/logistics/intake/:jobId continues
/// to work without router changes, while all photo logic lives in one place.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ops_stage_photo_screen.dart';

class OpsIntakePhotoScreen extends ConsumerWidget {
  final String jobId;
  final String customerId;

  const OpsIntakePhotoScreen({
    super.key,
    required this.jobId,
    required this.customerId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OpsStagePhotoScreen(
      jobId: jobId,
      customerId: customerId,
      stageKey: 'vehicle_intake',
    );
  }
}
