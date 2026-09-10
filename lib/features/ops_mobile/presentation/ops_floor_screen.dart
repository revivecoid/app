import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpsFloorScreen extends ConsumerWidget {
  const OpsFloorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workshop Floor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.build_circle_outlined, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            const Text('No active floor jobs yet.', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
