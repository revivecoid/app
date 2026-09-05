# -*- coding: utf-8 -*-
import re
import io

file_path = "lib/features/partner_dashboard/presentation/partner_dashboard_desktop.dart"

with io.open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add partner_dashboard_controller imports if missing
if "import 'partner_dashboard_controller.dart';" not in content:
    content = content.replace(
        "import 'package:flutter_riverpod/flutter_riverpod.dart';", 
        "import 'package:flutter_riverpod/flutter_riverpod.dart';\nimport 'partner_dashboard_controller.dart';"
    )

# 2. Add build method variables
build_method_sig = "Widget build(BuildContext context, WidgetRef ref) {"
build_method_vars = """Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(partnerMetricsDerivedProvider);
    final jobsAsync = ref.watch(partnerJobsDerivedProvider);
"""
content = content.replace(build_method_sig, build_method_vars)

# 3. Replace Filter Pills
filter_pills_pattern = re.compile(r'// FILTER PILLS.*?const SizedBox\(height: 32\),', re.DOTALL)
filter_pills_replacement = u"""// FILTER PILLS
                        metricsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (err, stack) => Text('Error: $err'),
                          data: (metrics) => SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _FilterPill(text: 'All Jobs', count: '${metrics['activeInShop']}', isActive: true),
                                const SizedBox(width: 8),
                                _FilterPill(text: 'Intake & Scheduled', count: '${metrics['intakeScheduled']}'),
                                const SizedBox(width: 8),
                                _FilterPill(text: 'Active Bodywork', count: '${metrics['activeBodywork']}'),
                                const SizedBox(width: 8),
                                _FilterPill(text: 'Paint Chamber', count: '${metrics['paintChamber']}'),
                                const SizedBox(width: 8),
                                _FilterPill(text: 'QC & Handover', count: '${metrics['qualityInspection'] + metrics['readyForHandover']}'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),"""
content = filter_pills_pattern.sub(filter_pills_replacement, content)

# 4. Replace KPI Cards
kpi_cards_pattern = re.compile(r'// KPI CARDS.*?const SizedBox\(height: 32\),', re.DOTALL)
kpi_cards_replacement = u"""// KPI CARDS
                        metricsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (err, stack) => Text('Error: $err'),
                          data: (metrics) => Row(
                            children: [
                              Expanded(
                                child: _KPICard(
                                  title: 'Active in Shop',
                                  icon: Icons.directions_car,
                                  iconColor: primary,
                                  value: '${metrics['activeInShop']}',
                                  subtitle: 'Vehicles',
                                  bottomText: '2 Bays Available',
                                  bottomSubText: 'Bay Load 90%',
                                  bottomSubTextColor: primary,
                                  hasBgHighlight: true,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _KPICard(
                                  title: 'Panels in Repair',
                                  icon: Icons.build_circle_outlined,
                                  iconColor: secondary,
                                  value: '${metrics['panelsInRepair']}',
                                  subtitle: 'Panels Active',
                                  bottomWidget: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _DotText(color: secondary, text: '8 PDR'),
                                      _DotText(color: primary, text: '22 Spray'),
                                      _DotText(color: tertiary, text: '12 Alignment'),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _KPICard(
                                  title: 'Avg Turnaround SLA',
                                  icon: Icons.timer_outlined,
                                  iconColor: onSurfaceVariant,
                                  value: '${metrics['avgTurnaroundSla']}',
                                  subtitle: 'Hours Avg',
                                  bottomText: '98.2% On-Time SLA',
                                  bottomTextBold: true,
                                  bottomSubWidget: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: emerald50, borderRadius: BorderRadius.circular(4)),
                                    child: const Text('Delta -1.2h', style: TextStyle(color: emerald600, fontSize: 14, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _KPICard(
                                  title: "Today's Handover",
                                  icon: Icons.fact_check_outlined,
                                  iconColor: primary,
                                  value: '${metrics['todayHandover']}',
                                  subtitle: 'Units Ready',
                                  bottomText: '3 Valet • 2 Pickup',
                                  bottomSubWidget: Row(
                                    children: [
                                      const Icon(Icons.check_circle_outline, color: emerald700, size: 14),
                                      const SizedBox(width: 4),
                                      const Text('All Inspected', style: TextStyle(color: emerald700, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  hasBottomBg: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),"""
content = kpi_cards_pattern.sub(kpi_cards_replacement, content)

# 5. Replace Swimlanes
swimlanes_pattern = re.compile(r'// SWIMLANES.*?Row\(\s*crossAxisAlignment: CrossAxisAlignment\.start,\s*children: \[(.*?)\]\s*\),', re.DOTALL)
swimlanes_replacement = u"""// SWIMLANES
                        jobsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (err, stack) => Text('Error: $err'),
                          data: (jobs) {
                            final intakeJobs = jobs.where((j) => (j.status ?? '').startsWith('1_') || (j.status ?? '').startsWith('2_') || (j.status ?? '').startsWith('3_') || (j.status ?? '').startsWith('4_') || (j.status ?? '').startsWith('5_')).toList();
                            final bodyJobs = jobs.where((j) => (j.status ?? '').startsWith('6_')).toList();
                            final paintJobs = jobs.where((j) => (j.status ?? '').startsWith('7_')).toList();
                            final qcJobs = jobs.where((j) => (j.status ?? '').startsWith('8_') || (j.status ?? '').startsWith('9_')).toList();
                            
                            Widget buildJobCard(PartnerJobNode job) {
                              final status = job.status ?? '';
                              final title = '${job.carMake} ${job.carModel}'.trim();
                              final subtitle = '${job.licensePlate} • ${job.customerName}';
                              final ro = 'RO-${job.id.length > 4 ? job.id.substring(0, 4) : job.id}';
                              
                              if (status.startsWith('1_') || status.startsWith('2_') || status.startsWith('3_') || status.startsWith('4_') || status.startsWith('5_')) {
                                return _JobCard(
                                  tagText: 'Intake', tagColor: errorContainer, tagTextColor: onErrorContainer,
                                  ro: ro, title: title.isEmpty ? 'Unknown Vehicle' : title, subtitle: subtitle,
                                  panelsTitle: 'Pending Assessment', panelsDesc: 'Awaiting tech allocation',
                                  etaText: 'TBD', person: 'Unassigned',
                                );
                              } else if (status.startsWith('6_')) {
                                return _JobCardBody(
                                  tag1: 'In Progress', tag1Bg: surfaceContainerHigh, tag1Color: onSurface,
                                  ro: ro, title: title.isEmpty ? 'Unknown Vehicle' : title, subtitle: subtitle,
                                  desc: 'Active bodywork & prep',
                                  progressText: 'Bodywork', progressValue: '50%', progressColor: secondary,
                                  iconBottom: Icons.tune, iconBottomText: 'Bay #01', iconBottomColor: secondary,
                                  person: 'Technician',
                                );
                              } else if (status.startsWith('7_')) {
                                return _JobCardPaint(
                                  ro: ro, title: title.isEmpty ? 'Unknown Vehicle' : title, subtitle: subtitle,
                                  desc: 'Paint & Curing Stage', person: 'Painter',
                                );
                              } else {
                                return _JobCardQC(
                                  ro: ro, title: title.isEmpty ? 'Unknown Vehicle' : title, subtitle: subtitle,
                                );
                              }
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _Swimlane(
                                    title: 'Intake & Admitted',
                                    color: tertiary,
                                    count: '${intakeJobs.length}',
                                    children: intakeJobs.map((j) => buildJobCard(j)).toList(),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _Swimlane(
                                    title: 'Active Bodywork',
                                    color: secondary,
                                    count: '${bodyJobs.length}',
                                    children: bodyJobs.map((j) => buildJobCard(j)).toList(),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _Swimlane(
                                    title: 'Paint Chamber',
                                    color: primary,
                                    count: '${paintJobs.length}',
                                    children: paintJobs.map((j) => buildJobCard(j)).toList(),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _Swimlane(
                                    title: 'QC & Handover',
                                    color: emerald500,
                                    count: '${qcJobs.length}',
                                    children: qcJobs.map((j) => buildJobCard(j)).toList(),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),"""
content = swimlanes_pattern.sub(swimlanes_replacement, content)

with io.open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("Updated successfully")
