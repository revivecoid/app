import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpsLogisticsScreen extends ConsumerWidget {
  const OpsLogisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logistics & Valet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_shipping_outlined, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            const Text('No vehicles waiting for pickup.', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
