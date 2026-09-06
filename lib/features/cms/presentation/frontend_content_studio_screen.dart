import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';
import '../../../core/widgets/responsive_layout_guard.dart';

class FrontendContentStudioScreen extends StatefulWidget {
  const FrontendContentStudioScreen({super.key});

  @override
  State<FrontendContentStudioScreen> createState() => _FrontendContentStudioScreenState();
}

class _FrontendContentStudioScreenState extends State<FrontendContentStudioScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _contentKeys = [];

  @override
  void initState() {
    super.initState();
    _fetchContent();
  }

  Future<void> _fetchContent() async {
    try {
      final response = await Supabase.instance.client
          .from('frontend_content')
          .select()
          .order('key_name', ascending: true);
      setState(() {
        _contentKeys = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching frontend content: $e');
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
                    Text('Frontend Content Studio', style: theme.textTheme.headlineLarge),
                    const SizedBox(height: 8),
                    Text('Manage dynamic text, hero copies, and translations for the public landing pages.', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _fetchContent,
                icon: const Icon(Icons.add),
                label: const Text('New Key'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_contentKeys.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(child: Text('No content keys found.')),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: theme.colorScheme.shadow, blurRadius: 10)],
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _contentKeys.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _contentKeys[index];
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(item['key_name']?.toString() ?? 'unknown_key', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () {},
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(item['content_value']?.toString() ?? 'Empty content', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  );
                },
              ),
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
            constraints: const BoxConstraints(maxWidth: 1000),
            child: content,
          ),
        ),
      ),
    );
  }
}
