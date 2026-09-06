import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';
import '../../../core/widgets/responsive_layout_guard.dart';

class DigitalAssetManagerScreen extends StatefulWidget {
  const DigitalAssetManagerScreen({super.key});

  @override
  State<DigitalAssetManagerScreen> createState() => _DigitalAssetManagerScreenState();
}

class _DigitalAssetManagerScreenState extends State<DigitalAssetManagerScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _assets = [];

  @override
  void initState() {
    super.initState();
    _fetchAssets();
  }

  Future<void> _fetchAssets() async {
    try {
      final response = await Supabase.instance.client
          .from('digital_assets')
          .select()
          .order('created_at', ascending: false);
      setState(() {
        _assets = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching assets: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    Widget content = SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Digital Asset Manager', style: theme.textTheme.headlineLarge),
                    const SizedBox(height: 8),
                    Text('Manage global brand images, vehicle 3D blueprints, and marketing banners.', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _fetchAssets,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload Asset'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_assets.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(child: Text('No digital assets found in global storage.')),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 250,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.8,
              ),
              itemCount: _assets.length,
              itemBuilder: (context, index) {
                final asset = _assets[index];
                return Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: theme.colorScheme.shadow, blurRadius: 8)],
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: asset['url'] != null
                              ? Image.network(asset['url'], fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.broken_image))
                              : const Icon(Icons.image, size: 48),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(asset['file_name']?.toString() ?? 'Unnamed Asset', style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(asset['file_type']?.toString().toUpperCase() ?? 'JPG', style: theme.textTheme.labelSmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: const ReVAppBar(),
      body: ResponsiveLayoutGuard(
        mobileWidget: content,
        desktopWidget: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: content,
          ),
        ),
      ),
    );
  }
}
