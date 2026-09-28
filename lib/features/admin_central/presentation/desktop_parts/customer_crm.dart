part of '../master_admin_desktop.dart';

// ─── Customer CRM ─────────────────────────────────────────────────────────────

class _CustomerCrmContent extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  const _CustomerCrmContent(
      {required this.cs, required this.state});

  void _showCustomerDetail(BuildContext context, CustomerCrmNode c) {
    final supabase = Supabase.instance.client;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => FutureBuilder<List<Map<String, dynamic>>>(
          future: supabase
              .rpc('get_customer_jobs', params: {'p_customer_id': c.id})
              .then((res) {
            if (res == null) return <Map<String, dynamic>>[];
            final list = res as List;
            return list.cast<Map<String, dynamic>>();
          }),
          builder: (ctx, snap) {
            // C-30 fix: show error separately from empty state
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 32),
                  const SizedBox(height: 8),
                  Text('Gagal memuat riwayat: ${snap.error}',
                      style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                ]),
              );
            }
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ));
            }
            final jobs = snap.data ?? [];
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(24),
              children: [
                // Header
                Row(children: [
                  Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: cs.primary, shape: BoxShape.circle),
                      child: Icon(Icons.person_rounded,
                          color: cs.onPrimary, size: 26)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(c.fullName,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface)),
                      Text(c.email,
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  IconButton(
                      icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
                const Divider(height: 28),
                // Contact info
                _InfoRow(cs: cs, label: 'Phone', value: c.phone),
                _InfoRow(cs: cs, label: 'Customer ID', value: c.id),
                const SizedBox(height: 20),
                // Jobs header
                Text('Repair History',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                const SizedBox(height: 10),
                if (snap.connectionState == ConnectionState.waiting)
                  Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                              color: cs.primary)))
                else if (jobs.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No repair jobs found.',
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant)))
                else
                  ...jobs.map((job) {
                    final v = job['vehicles'] as Map<String, dynamic>? ?? {};
                    final p = job['partners'] as Map<String, dynamic>? ?? {};
                    final status = job['status']?.toString() ?? '';
                    final price = job['final_cost'];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: cs.outlineVariant.withValues(
                                  alpha: 0.5))),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                            Text(
                                '${v['make'] ?? ''} ${v['model'] ?? ''} · ${v['license_plate'] ?? ''}',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface)),
                            const SizedBox(height: 2),
                            Text(
                                p['shop_name']?.toString() ??
                                    'Unassigned',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant)),
                          ]),
                        ),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                          _StatusChip(status: status, cs: cs),
                          if (price != null) ...[
                            const SizedBox(height: 4),
                            Text(
                                'Rp ${NumberFormat('#,###').format(price)}',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary)),
                          ]
                        ]),
                      ]),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Text('Customer Database',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: cs.onSurface)),
      const SizedBox(height: 6),
      Text('${state.customers.length} registered customers',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      const SizedBox(height: 20),
      ...state.customers.map((c) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: cs.onSurface.withValues(alpha: 0.04),
                      blurRadius: 4)
                ]),
            child: ListTile(
              onTap: () => _showCustomerDetail(context, c),
              hoverColor: cs.primary.withValues(alpha: 0.05),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              leading: CircleAvatar(
                  backgroundColor: cs.primary.withValues(alpha: 0.15),
                  child: Text(
                      c.fullName.isNotEmpty
                          ? c.fullName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cs.primary))),
              title: Text(c.fullName,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              subtitle: Text('${c.email} · ${c.phone}',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant)),
              trailing: Icon(Icons.chevron_right,
                  color: cs.onSurfaceVariant, size: 18),
            ),
          )),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final String value;
  const _InfoRow(
      {required this.cs, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: cs.onSurfaceVariant))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface))),
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final ColorScheme cs;
  const _StatusChip({required this.status, required this.cs});

  @override
  Widget build(BuildContext context) {
    final label = jobStatusLabel(status, english: true); // S-08 fix: single source
    final color = switch (status) {
      '6_in_progress' => const Color(0xFF0ea5e9),
      '7_finished' || '8_awaiting_delivery' => const Color(0xFFf59e0b),
      '9_done' || 'completed' => const Color(0xFF10b981),
      _ => cs.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}


