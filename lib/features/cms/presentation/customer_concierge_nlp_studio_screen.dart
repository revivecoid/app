import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';
import '../../../core/widgets/responsive_layout_guard.dart';

class CustomerConciergeNlpStudioScreen extends StatefulWidget {
  const CustomerConciergeNlpStudioScreen({super.key});

  @override
  State<CustomerConciergeNlpStudioScreen> createState() => _CustomerConciergeNlpStudioScreenState();
}

class _CustomerConciergeNlpStudioScreenState extends State<CustomerConciergeNlpStudioScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _intents = [];

  @override
  void initState() {
    super.initState();
    _fetchIntents();
  }

  Future<void> _fetchIntents() async {
    try {
      final response = await Supabase.instance.client
          .from('nlp_intents')
          .select()
          .order('created_at', ascending: false);
      setState(() {
        _intents = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching intents: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    
    Widget content = SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Customer Concierge AI NLP Studio', style: theme.textTheme.headlineLarge),
                    const SizedBox(height: 8),
                    Text('Manage NLP intents, training phrases, and chatbot routing rules.', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _fetchIntents,
                icon: const Icon(Icons.refresh),
                label: const Text('Sync NLP Models'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_intents.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(child: Text('No intents found in the database. NLP engine might be offline.')),
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
                itemCount: _intents.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final intent = _intents[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
                      child: Icon(Icons.psychology, color: theme.colorScheme.primary),
                    ),
                    title: Text(intent['intent_name']?.toString() ?? 'Unknown Intent', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(intent['training_phrases']?.toString() ?? 'No phrases trained'),
                    trailing: Switch(
                      value: intent['is_active'] ?? true,
                      onChanged: (val) {},
                      activeColor: theme.colorScheme.primary,
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
