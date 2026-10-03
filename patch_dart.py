import os

file_path = "lib/features/admin_central/presentation/master_admin_desktop.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

start_idx = content.find("class _WorkshopSettingsContent extends StatelessWidget")
end_idx = content.find("class _AssignJobsContent extends ConsumerStatefulWidget")

new_class = """class _WorkshopSettingsContent extends StatefulWidget {
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
          onPressed: () => context.push('/admin-central/partner/new'),
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
                  activeColor: cs.primary,
                  onChanged: (val) {
                    controller.updateAutoAssignSettings({'is_active': val});
                  },
                ),
              ],
            ),
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
                          mode == 'fill_first' ? 'Fills highest priority workshops to capacity before assigning to lower tiers.'
                          : mode == 'strict_priority' ? 'Always tries to assign to the highest priority workshop with available capacity.'
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
              final bool aaActive = p.raw['auto_assign_active'] == true;
              final int priority = p.raw['auto_assign_priority'] ?? 999;
              final int capacity = p.raw['auto_assign_capacity'] ?? 10;
              final int activeJobs = p.activeJobsCount;
              
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
                                Text(p.status.toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: p.status == 'active' ? cs.primary : cs.error)),
                              ])),
                        ])),
                    Expanded(
                        flex: 3,
                        child: Text(p.serviceArea, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
                    Expanded(
                        flex: 2,
                        child: Switch(
                          value: aaActive,
                          activeColor: cs.primary,
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
                            Text(activeJobs.toString() + ' / ' + capacity.toString(), style: TextStyle(color: activeJobs >= capacity ? cs.error : cs.onSurface)),
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
        title: Text('Edit ' + title),
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
"""

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content[:start_idx] + new_class + content[end_idx:])
print("Patched.")
