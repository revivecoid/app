import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/rev_app_bar.dart';
import '../../../core/widgets/responsive_layout_guard.dart';

class CommissionSettlementEngineScreen extends StatefulWidget {
  const CommissionSettlementEngineScreen({super.key});

  @override
  State<CommissionSettlementEngineScreen> createState() => _CommissionSettlementEngineScreenState();
}

class _CommissionSettlementEngineScreenState extends State<CommissionSettlementEngineScreen> {
  bool _isLoading = true;
  String? _error;  // BIZ-11: distinguish error from empty
  List<Map<String, dynamic>> _settlements = [];

  @override
  void initState() {
    super.initState();
    _fetchSettlements();
  }

  Future<void> _fetchSettlements() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      // BIZ-11 fix: query partner_settlements view (created in F5 migration)
      // Falls back to empty list if view not yet applied
      final response = await Supabase.instance.client
          .from('partner_settlements')
          .select()
          .order('settlement_date', ascending: false)
          .limit(100);
      setState(() {
        _settlements = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      // BIZ-11 fix: show error explicitly, not silent empty
      debugPrint('Error fetching settlements: $e');
      setState(() {
        _isLoading = false;
        _error = 'Gagal memuat data settlement: ${e.toString().replaceAll('Exception:', '').trim()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // BIZ-11: show error state explicitly
    if (!_isLoading && _error != null) {
      return Scaffold(
        appBar: const ReVAppBar(title: Text('Settlement & Komisi')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchSettlements, child: const Text('Coba lagi')),
          ]),
        )),
      );
    }

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
      backgroundColor: theme.colorScheme.surface,
      appBar: const ReVAppBar(showBackButton: true),
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
