part of '../master_admin_desktop.dart';

// ─── Workshop Settings & Quotas ───────────────────────────────────────────────

class _WorkshopSettingsContent extends StatefulWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final AdminDashboardController controller;
  const _WorkshopSettingsContent(
      {required this.cs,
      required this.state,
      required this.controller});

  @override
  State<_WorkshopSettingsContent> createState() => _WorkshopSettingsContentState();
}

class _WorkshopSettingsContentState extends State<_WorkshopSettingsContent> {
  ColorScheme get cs => widget.cs;
  AdminDashboardState get state => widget.state;
  AdminDashboardController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final settings = state.autoAssignSettings;
    final bool isEngineActive = settings?.containsKey('is_active') == true ? (settings!['is_active'] == true) : false;
    final bool matchLocation = settings?.containsKey('match_location') == true ? (settings!['match_location'] == true) : true;
    final String mode = settings?['mode'] ?? 'strict_priority';

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Row(children: [
        _Chip(
            cs: cs,
            label: 'Workshop Settings & Quotas',
            bgColor: cs.surfaceContainerHigh,
            fgColor: cs.primary),
        const Spacer(),
        ElevatedButton.icon(
          // C-27 fix: 'partner/new' doesn't exist — redirect to pending applications
          // which is the real onboarding entry point
          onPressed: () => context.push('/admin-central/applications'),
          icon: Icon(Icons.add, size: 16, color: cs.onPrimary),
          label: Text('Register Workshop', style: TextStyle(color: cs.onPrimary)),
          style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        ),
      ]),
      const SizedBox(height: 16),

      // Engine Master Panel
      Container(
        decoration: BoxDecoration(
          color: isEngineActive ? cs.primaryContainer.withValues(alpha: 0.15) : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEngineActive ? cs.primary.withValues(alpha: 0.3) : cs.surfaceContainerHigh,
            width: 1.5,
          )
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: isEngineActive ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('Auto-Assignment Engine', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
                const Spacer(),
                Switch(
                  value: isEngineActive,
                  activeThumbColor: cs.primary,
                  onChanged: (val) {
                    controller.updateAutoAssignSettings({'is_active': val});
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            // Valet fee editor (admin)
            _AdminValetFeeEditor(cs: cs),
            const SizedBox(height: 16),
            const Divider(),
            if (isEngineActive) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Allocation Strategy', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'fill_first', label: Text('Fill Priority')),
                            ButtonSegment(value: 'strict_priority', label: Text('Strict Priority')),
                            ButtonSegment(value: 'round_robin', label: Text('Evenly Distribute')),
                          ],
                          selected: {mode},
                          onSelectionChanged: (Set<String> newSelection) {
                            controller.updateAutoAssignSettings({'mode': newSelection.first});
                          },
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          mode == 'fill_first' ? 'Round-robin across the priority queue, but a higher priority workshop jumps in whenever it is completely empty.'
                          : mode == 'strict_priority' ? 'Always assigns to the highest priority workshop that has ANY open slot.'
                          : 'Distributes jobs evenly (round robin) across workshops according to priority queue.',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Location Matching', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Checkbox(
                              value: matchLocation,
                              onChanged: (val) {
                                controller.updateAutoAssignSettings({'match_location': val});
                              },
                            ),
                            Text('Require exact Service Area match', style: TextStyle(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ]
          ],
        ),
      ),
      const SizedBox(height: 24),

      // Partner table
      if (state.isLoading)
        Center(child: CircularProgressIndicator(color: cs.primary))
      else if (state.partners.isEmpty)
        _InfoBox(
            cs: cs,
            icon: Icons.warehouse_outlined,
            title: 'No Workshops Registered',
            subtitle: 'Use "Register Workshop" to onboard your first partner hub.')
      else
        Container(
          decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: cs.onSurface.withValues(alpha: 0.04), blurRadius: 8)
              ]),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            // Header
            Container(
              color: cs.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                _TH(cs: cs, label: 'Workshop', flex: 4),
                _TH(cs: cs, label: 'Area', flex: 3),
                _TH(cs: cs, label: 'Auto-Assign', flex: 2),
                _TH(cs: cs, label: 'Priority Q', flex: 2),
                _TH(cs: cs, label: 'Capacity', flex: 2),
                _TH(cs: cs, label: 'Actions', flex: 2, right: true),
              ]),
            ),
            ...state.partners.map((p) {
              final bool aaActive = p.autoAssignActive;
              final int priority = p.autoAssignPriority;
              final int capacity = p.autoAssignCapacity;
              final int activeJobs = p.activeVolume;
              
              return Container(
                  decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: cs.surfaceContainerHigh, width: 1))),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                        flex: 4,
                        child: Row(children: [
                          Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                  color: cs.primaryContainer.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Icon(Icons.warehouse, size: 16, color: cs.primary)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(p.shopName,
                                    style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                Text((p.isActive ? 'ACTIVE' : 'INACTIVE'),
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: p.isActive ? cs.primary : cs.error)),
                              ])),
                        ])),
                    Expanded(
                        flex: 3,
                        child: Text(p.serviceArea ?? 'Unknown', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
                    Expanded(
                        flex: 2,
                        child: Switch(
                          value: aaActive,
                          activeThumbColor: cs.primary,
                          onChanged: (val) {
                            controller.updatePartnerAutoAssignSettings(p.id, {'auto_assign_active': val});
                          },
                        )),
                    Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Text(priority.toString(), style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 14),
                              onPressed: () {
                                _editNumber(context, 'Priority Queue', priority, (val) {
                                  controller.updatePartnerAutoAssignSettings(p.id, {'auto_assign_priority': val});
                                });
                              },
                            )
                          ],
                        )),
                    Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Text('$activeJobs / $capacity', style: TextStyle(color: activeJobs >= capacity ? cs.error : cs.onSurface)),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 14),
                              onPressed: () {
                                _editNumber(context, 'Max Capacity', capacity, (val) {
                                  controller.updatePartnerAutoAssignSettings(p.id, {'auto_assign_capacity': val});
                                });
                              },
                            )
                          ],
                        )),
                    Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => context.push('/admin-central/partner/${p.id}'),
                            child: const Text('View'),
                          ),
                        )),
                  ]));
            }),
          ]),
        ),
    ]);
  }

  void _editNumber(BuildContext context, String title, int current, Function(int) onSave) {
    final ctrl = TextEditingController(text: current.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $title'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(ctrl.text);
              if (val != null) {
                onSave(val);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      )
    );
  }
}
class _AssignJobsContent extends ConsumerStatefulWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final AdminDashboardController controller;

  const _AssignJobsContent(
      {required this.cs,
      required this.state,
      required this.controller});

  @override
  ConsumerState<_AssignJobsContent> createState() =>
      _AssignJobsContentState();
}

class _AssignJobsContentState
    extends ConsumerState<_AssignJobsContent> {
  final Set<String> _selected = {};

  ColorScheme get cs => widget.cs;
  AdminDashboardState get state => widget.state;
  AdminDashboardController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    // Surface assignment success / error as snackbars
    ref.listen<AdminDashboardState>(adminDashboardProvider, (prev, next) {
      if (next.successMessage != null &&
          next.successMessage != prev?.successMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(next.successMessage!),
          ]),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 3),
        ));
      }
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(next.errorMessage!)),
          ]),
          backgroundColor: cs.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 5),
        ));
      }
    });

    final jobs = state.assignJobsFiltered;
    final partners = state.partners.where((p) => p.isActive).toList();

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      // Header
      Row(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          _Chip(
              cs: cs,
              label: 'Assign Jobs Hub',
              bgColor: cs.surfaceContainerHigh,
              fgColor: cs.primary),
          const SizedBox(height: 6),
          Text('Job Assignment & Dispatch Matrix',
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          Text(
              '${jobs.length} job(s) matching filters · ${state.partners.length} active hub(s)',
              style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant)),
        ])),
        if (_selected.isNotEmpty)
          ElevatedButton.icon(
            onPressed: () => _showBulkAssignDialog(
                context, partners),
            icon: Icon(Icons.assignment_turned_in_rounded,
                size: 16, color: cs.onPrimary),
            label: Text(
                'Bulk Assign ${_selected.length} Jobs',
                style: TextStyle(color: cs.onPrimary)),
            style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
          ),
      ]),
      const SizedBox(height: 16),

      // Filter bar
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: cs.onSurface.withValues(alpha: 0.04),
                  blurRadius: 8)
            ]),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          // Assignment status
          _FilterChipGroup<AssignStatusFilter>(
            cs: cs,
            label: 'Status',
            options: const [
              (AssignStatusFilter.all, 'All'),
              (AssignStatusFilter.unassigned, 'Unassigned'),
              (AssignStatusFilter.assigned, 'Assigned'),
              (AssignStatusFilter.inProgress, 'In Progress'),
            ],
            selected: state.assignStatusFilter,
            onSelected: controller.setAssignStatusFilter,
          ),
          const SizedBox(width: 8),
          // Payment status
          _FilterChipGroup<PaymentStatusFilter>(
            cs: cs,
            label: 'Payment',
            options: const [
              (PaymentStatusFilter.all, 'All'),
              (PaymentStatusFilter.pending, 'Pending'),
              (PaymentStatusFilter.paid, 'Paid'),
              (PaymentStatusFilter.overdue, 'Overdue'),
            ],
            selected: state.assignPaymentFilter,
            onSelected: controller.setAssignPaymentFilter,
          ),
          const SizedBox(width: 8),
          // Date range
          OutlinedButton.icon(
            onPressed: () =>
                _pickDateRange(context),
            icon: Icon(Icons.date_range_outlined,
                size: 14, color: cs.onSurface),
            label: Text(
                state.assignDateFrom != null
                    ? '${DateFormat('d MMM').format(state.assignDateFrom!)} – ${state.assignDateTo != null ? DateFormat('d MMM').format(state.assignDateTo!) : '...'}'
                    : 'Date Range',
                style:
                    TextStyle(color: cs.onSurface, fontSize: 12)),
            style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.outline),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
          ),
          if (state.assignDateFrom != null)
            IconButton(
                icon: Icon(Icons.close,
                    size: 16, color: cs.onSurfaceVariant),
                onPressed: () => controller.setAssignDateRange(
                    null, null)),
        ]),
      ),
      const SizedBox(height: 16),

      // Table
      Container(
        decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: cs.onSurface.withValues(alpha: 0.04),
                  blurRadius: 8)
            ]),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          // Table header with sort
          Container(
            color: cs.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            child: Row(children: [
              SizedBox(
                  width: 36,
                  child: Checkbox(
                    value: _selected.length == jobs.length &&
                        jobs.isNotEmpty,
                    tristate: true,
                    activeColor: cs.primary,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.addAll(jobs.map((j) => j.id));
                      } else {
                        _selected.clear();
                      }
                    }),
                  )),
              _SortHeader(
                  cs: cs,
                  label: 'Job ID',
                  flex: 2,
                  field: AssignSortField.createdAt,
                  current: state.assignSortField,
                  asc: state.assignSortAsc,
                  onSort: controller.setAssignSort),
              _SortHeader(
                  cs: cs,
                  label: 'Vehicle',
                  flex: 3,
                  field: AssignSortField.vehicle,
                  current: state.assignSortField,
                  asc: state.assignSortAsc,
                  onSort: controller.setAssignSort),
              _SortHeader(
                  cs: cs,
                  label: 'Customer',
                  flex: 3,
                  field: AssignSortField.customerName,
                  current: state.assignSortField,
                  asc: state.assignSortAsc,
                  onSort: controller.setAssignSort),
              _SortHeader(
                  cs: cs,
                  label: 'Assign Status',
                  flex: 3,
                  field: AssignSortField.assignStatus,
                  current: state.assignSortField,
                  asc: state.assignSortAsc,
                  onSort: controller.setAssignSort),
              _SortHeader(
                  cs: cs,
                  label: 'Payment',
                  flex: 2,
                  field: AssignSortField.paymentStatus,
                  current: state.assignSortField,
                  asc: state.assignSortAsc,
                  onSort: controller.setAssignSort),
              _TH(
                  cs: cs,
                  label: 'Assign To',
                  flex: 3,
                  right: true),
            ]),
          ),

          if (state.isLoading)
            Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                    child: CircularProgressIndicator(
                        color: cs.primary)))
          else if (jobs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                  child: Text('No jobs match the current filters.',
                      style: TextStyle(
                          color: cs.onSurfaceVariant))),
            )
          else
            ...jobs.map((j) => _AssignRow(
                  cs: cs,
                  job: j,
                  partners: partners,
                  isSelected: _selected.contains(j.id),
                  onToggleSelect: () => setState(() {
                    if (_selected.contains(j.id)) {
                      _selected.remove(j.id);
                    } else {
                      _selected.add(j.id);
                    }
                  }),
                  onAssign: (partnerId, partnerName) =>
                      controller.assignJobToPartner(
                          j.id, partnerId, partnerName),
                  onUnassign: () =>
                      controller.unassignJob(j.id),
                )),
        ]),
      ),
    ]);
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate:
          DateTime.now().subtract(const Duration(days: 180)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      initialDateRange: state.assignDateFrom != null
          ? DateTimeRange(
              start: state.assignDateFrom!,
              end: state.assignDateTo ??
                  DateTime.now())
          : null,
    );
    if (range != null) {
      controller.setAssignDateRange(
          range.start, range.end);
    }
  }

  void _showBulkAssignDialog(
      BuildContext context, List<PartnerCrmNode> partners) {
    showDialog(
      context: context,
      builder: (ctx) {
        String? selectedId;
        String? selectedName;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            backgroundColor:
                cs.surfaceContainerLowest,
            title: Text(
                'Bulk Assign ${_selected.length} Jobs',
                style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700)),
            content: DropdownButtonFormField<String>(
              decoration: InputDecoration(
                  labelText: 'Select Workshop',
                  labelStyle: TextStyle(
                      color: cs.onSurfaceVariant)),
              items: partners
                  .map((p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(p.shopName,
                          style: TextStyle(
                              color: cs.onSurface))))
                  .toList(),
              onChanged: (v) {
                selectedId = v;
                selectedName = partners
                    .firstWhere((p) => p.id == v)
                    .shopName;
              },
            ),
            actions: [
              TextButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(),
                  child: Text('Cancel',
                      style: TextStyle(
                          color: cs.onSurfaceVariant))),
              ElevatedButton(
                onPressed: () async {
                  if (selectedId == null) return;
                  for (final id in _selected) {
                    await controller.assignJobToPartner(
                        id, selectedId!, selectedName!);
                  }
                  setState(() => _selected.clear());
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary),
                child: Text('Assign All',
                    style:
                        TextStyle(color: cs.onPrimary)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AssignRow extends StatefulWidget {
  final ColorScheme cs;
  final AdminJobNode job;
  final List<PartnerCrmNode> partners;
  final bool isSelected;
  final VoidCallback onToggleSelect;
  final Future<void> Function(String id, String name) onAssign;
  final VoidCallback onUnassign;

  const _AssignRow(
      {required this.cs,
      required this.job,
      required this.partners,
      required this.isSelected,
      required this.onToggleSelect,
      required this.onAssign,
      required this.onUnassign});

  @override
  State<_AssignRow> createState() => _AssignRowState();
}

class _AssignRowState extends State<_AssignRow> {
  String? _pendingPartnerId;
  bool _confirming = false;

  ColorScheme get cs => widget.cs;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final partners = widget.partners;
    final hasPending = _pendingPartnerId != null &&
        _pendingPartnerId != job.partnerId;

    return Container(
      decoration: BoxDecoration(
          color: widget.isSelected
              ? cs.primaryContainer.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border(
              bottom: BorderSide(
                  color: cs.surfaceContainerHigh, width: 1))),
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 10),
      child: Row(children: [
        SizedBox(
            width: 36,
            child: Checkbox(
              value: widget.isSelected,
              activeColor: cs.primary,
              onChanged: (_) => widget.onToggleSelect(),
            )),
        // Job ID
        Expanded(
            flex: 2,
            child: Text('#${job.id}',
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface,
                    fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis)),
        // Vehicle
        Expanded(
            flex: 3,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                  job.carIdentity.contains('-')
                      ? job.carIdentity.split('-').first.trim()
                      : job.carIdentity,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface),
                  overflow: TextOverflow.ellipsis),
              if (job.carIdentity.contains('-'))
                Text(
                    job.carIdentity.split('-').last.trim(),
                    style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant)),
            ])),
        // Customer
        Expanded(
            flex: 3,
            child: Text(job.customerName,
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface),
                overflow: TextOverflow.ellipsis)),
        // Assign status
        Expanded(
            flex: 3,
            child: job.isUnassigned
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: cs.secondaryContainer
                            .withValues(alpha: 0.3),
                        borderRadius:
                            BorderRadius.circular(20)),
                    child: Text('UNASSIGNED',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.onSecondaryContainer)))
                : Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                    Text(job.partnerName,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.primary),
                        overflow: TextOverflow.ellipsis),
                    Text(_statusLabel(job.status),
                        style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant)),
                  ])),
        // Payment
        Expanded(
            flex: 2,
            child: Text(
                job.isPaid ? 'PAID' : 'PENDING',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: job.isPaid
                        ? const Color(0xFF059669)
                        : cs.onSurfaceVariant))),
        // Assign to column — dropdown + confirm button
        Expanded(
            flex: 3,
            child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  if (!job.isUnassigned && !hasPending)
                    TextButton(
                        onPressed: widget.onUnassign,
                        child: Text('Unassign',
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.error))),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: hasPending
                                    ? cs.primary
                                    : cs.outline,
                                width: hasPending ? 1.5 : 1)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: hasPending
                                    ? cs.primary
                                    : cs.outline,
                                width: hasPending ? 1.5 : 1)),
                        hintText: 'Assign to...',
                        hintStyle: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant),
                      ),
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurface),
                      initialValue: _pendingPartnerId ?? job.partnerId,
                      items: partners
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.shopName,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurface)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _pendingPartnerId = v);
                        }
                      },
                    ),
                  ),
                  // Confirm button — only shown when a new partner is selected
                  if (hasPending) ...[
                    const SizedBox(width: 6),
                    _confirming
                        ? SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary))
                        : Tooltip(
                            message: 'Confirm assignment',
                            child: InkWell(
                              borderRadius:
                                  BorderRadius.circular(6),
                              onTap: () async {
                                final pid = _pendingPartnerId!;
                                final pName = partners
                                    .firstWhere(
                                        (p) => p.id == pid)
                                    .shopName;
                                setState(
                                    () => _confirming = true);
                                await widget.onAssign(
                                    pid, pName);
                                if (mounted) {
                                  setState(() {
                                    _confirming = false;
                                    _pendingPartnerId = null;
                                  });
                                }
                              },
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                    color: const Color(
                                        0xFF059669),
                                    borderRadius:
                                        BorderRadius.circular(
                                            6)),
                                child: const Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                    color: Colors.white),
                              ),
                            ),
                          ),
                    // Cancel / clear pending
                    Tooltip(
                      message: 'Clear selection',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => setState(
                            () => _pendingPartnerId = null),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                              color: cs.errorContainer
                                  .withValues(alpha: 0.5),
                              borderRadius:
                                  BorderRadius.circular(6)),
                          child: Icon(Icons.close_rounded,
                              size: 14, color: cs.error),
                        ),
                      ),
                    ),
                  ],
                ]))),
      ]),
    );
  }

  String _statusLabel(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty
          ? ''
          : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class _SortHeader extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final int flex;
  final AssignSortField field;
  final AssignSortField current;
  final bool asc;
  final ValueChanged<AssignSortField> onSort;

  const _SortHeader(
      {required this.cs,
      required this.label,
      required this.flex,
      required this.field,
      required this.current,
      required this.asc,
      required this.onSort});

  @override
  Widget build(BuildContext context) {
    final isActive = current == field;
    return Expanded(
        flex: flex,
        child: GestureDetector(
            onTap: () => onSort(field),
            child: Row(children: [
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? cs.primary
                          : cs.onSurfaceVariant,
                      letterSpacing: 0.5)),
              if (isActive)
                Icon(
                    asc
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 12,
                    color: cs.primary),
            ])));
  }
}

class _FilterChipGroup<T> extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  const _FilterChipGroup(
      {required this.cs,
      required this.label,
      required this.options,
      required this.selected,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label:',
          style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600)),
      const SizedBox(width: 4),
      ...options.map((o) {
        final isSelected = selected == o.$1;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: GestureDetector(
            onTap: () => onSelected(o.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: isSelected
                      ? cs.primaryContainer
                          .withValues(alpha: 0.4)
                      : cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: isSelected
                          ? cs.primary
                          : cs.outline.withValues(alpha: 0.3))),
              child: Text(o.$2,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: isSelected
                          ? cs.primary
                          : cs.onSurface)),
            ),
          ),
        );
      }),
    ]);
  }
}

