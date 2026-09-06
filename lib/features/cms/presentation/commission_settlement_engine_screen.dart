import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';
import '../../../core/widgets/responsive_layout_guard.dart';

class CommissionSettlementEngineScreen extends StatefulWidget {
  const CommissionSettlementEngineScreen({super.key});

  @override
  State<CommissionSettlementEngineScreen> createState() => _CommissionSettlementEngineScreenState();
}

class _CommissionSettlementEngineScreenState extends State<CommissionSettlementEngineScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _settlements = [];

  @override
  void initState() {
    super.initState();
    _fetchSettlements();
  }

  Future<void> _fetchSettlements() async {
    try {
      final response = await Supabase.instance.client
          .from('commission_settlements')
          .select()
          .order('created_at', ascending: false);
      setState(() {
        _settlements = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching settlements: $e');
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
                    Text('Commission Settlement Engine', style: theme.textTheme.headlineLarge),
                    const SizedBox(height: 8),
                    Text('Automated workshop payouts and margin index reporting.', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _fetchSettlements,
                icon: const Icon(Icons.calculate),
                label: const Text('Run Settlement Batch'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_settlements.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(child: Text('No settlement records found.')),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: theme.colorScheme.shadow, blurRadius: 10)],
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Partner ID')),
                    DataColumn(label: Text('Amount')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Date')),
                  ],
                  rows: _settlements.map((s) => DataRow(
                    cells: [
                      DataCell(Text(s['partner_id']?.toString() ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text('Rp ${s['amount']?.toString() ?? '0'}', style: TextStyle(color: theme.colorScheme.primary))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: s['status'] == 'paid' ? theme.colorScheme.tertiary.withValues(alpha: 0.2) : theme.colorScheme.errorContainer.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(s['status']?.toString().toUpperCase() ?? 'PENDING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: s['status'] == 'paid' ? theme.colorScheme.tertiary : theme.colorScheme.error)),
                        )
                      ),
                      DataCell(Text(s['created_at']?.toString().substring(0, 10) ?? 'N/A')),
                    ]
                  )).toList(),
                ),
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
            constraints: const BoxConstraints(maxWidth: 1200),
            child: content,
          ),
        ),
      ),
    );
  }
}
