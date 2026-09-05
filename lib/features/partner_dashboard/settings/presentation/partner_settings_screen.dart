import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Helper for exact colors matching the design system
class _DesignColors {
  static const surface = Color(0xFFFDF8F9);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF7F2F3);
  static const surfaceContainerHigh = Color(0xFFEBE7E8);
  static const surfaceContainerHighest = Color(0xFFE6E1E2);
  static const primary = Color(0xFFA40016);
  static const primaryContainer = Color(0xFFD10721);
  static const onPrimary = Color(0xFFFFFFFF);
  static const onPrimaryContainer = Color(0xFFFFE1DE);
  static const secondary = Color(0xFFA83900);
  static const secondaryContainer = Color(0xFFFC6018);
  static const onSecondary = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFF1C1B1C);
  static const onSurfaceVariant = Color(0xFF5D3F3D);
  static const emerald500 = Color(0xFF10B981);
  static const primaryFixed = Color(0xFFFFDAD7);
  static const secondaryFixed = Color(0xFFFFDBCF);
}

class PartnerSettingsScreen extends ConsumerStatefulWidget {
  const PartnerSettingsScreen({super.key});

  @override
  ConsumerState<PartnerSettingsScreen> createState() => _PartnerSettingsScreenState();
}

class _PartnerSettingsScreenState extends ConsumerState<PartnerSettingsScreen> {
  int _intakeQuota = 18;
  int _insurerQuota = 6;
  bool _isFastTrackActive = true;
  final TextEditingController _chatController = TextEditingController();

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _DesignColors.surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SIDEBAR
          _buildSidebar(),
          // MAIN CONTENT
          Expanded(
            child: Column(
              children: [
                // HEADER
                _buildHeader(),
                // CONTENT AREA
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // LEFT COLUMN (7/12 approx)
                        Expanded(
                          flex: 7,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(),
                              const SizedBox(height: 24),
                              _buildQuotaWidgets(),
                              const SizedBox(height: 24),
                              _buildCalendar(),
                              const SizedBox(height: 24),
                              _buildBlacklist(),
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Schedule & quota preferences updated. Dispatch matrix recalibrated.'),
                                        backgroundColor: _DesignColors.emerald500,
                                      )
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _DesignColors.primaryContainer,
                                    foregroundColor: _DesignColors.onPrimary,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.save, size: 20),
                                  label: const Text('Save Schedule Preferences', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        // RIGHT COLUMN (5/12 approx)
                        Expanded(
                          flex: 5,
                          child: _buildCommlink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 288,
      color: _DesignColors.surfaceContainerLowest,
      child: Column(
        children: [
          // Sidebar Header
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => context.go('/'),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/images/revive_logo.png',
                        height: 28,
                        color: _DesignColors.primaryContainer,
                      ),
                      const SizedBox(width: 8),
                      const Text('re-V', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _DesignColors.onSurface)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _DesignColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('OPS CORE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.primary, letterSpacing: 1.2)),
                ),
              ],
            ),
          ),
          // Hub Selection
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _DesignColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ACTIVE OPERATIONAL HUB', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warehouse, color: _DesignColors.primary, size: 18),
                          const SizedBox(width: 4),
                          const Text('Hub #04 - Kebon Jeruk', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _DesignColors.onSurface)),
                        ],
                      ),
                      const Icon(Icons.unfold_more, color: _DesignColors.onSurfaceVariant, size: 16),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Navigation
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _navItem(Icons.view_kanban, 'Job Board / Pipeline', false),
                _navItem(Icons.tune, 'Workshop Settings & Quotas', true),
                _navItem(Icons.grid_view, 'Master Matrix (Admin)', false),
                _navItem(Icons.forum, 'Customer Inquiries & Commlink', false),
                _navItem(Icons.speed, 'Analytics & Telemetry', false),
                _navItem(Icons.settings, 'System Settings', false),
              ],
            ),
          ),
          // Telemetry footer
          Container(
            padding: const EdgeInsets.all(16),
            color: _DesignColors.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('CORE TELEMETRY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant)),
                    const Text('v4.18.2', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _DesignColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: _DesignColors.emerald500, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          const Text('Active Sync: OK', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _DesignColors.onSurface)),
                        ],
                      ),
                      const Text('34ms', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? _DesignColors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: isActive ? _DesignColors.onPrimaryContainer : _DesignColors.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 14, fontWeight: isActive ? FontWeight.bold : FontWeight.w600, color: isActive ? _DesignColors.onPrimaryContainer : _DesignColors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: _DesignColors.surfaceContainerLowest.withValues(alpha: 0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Search
          SizedBox(
            width: 400,
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search VIN, license plate, or order ID",
                hintStyle: const TextStyle(color: _DesignColors.onSurfaceVariant, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: _DesignColors.onSurfaceVariant, size: 20),
                filled: true,
                fillColor: _DesignColors.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
          // Actions
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: _DesignColors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: _DesignColors.emerald500, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('NODE 04: LIVE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _DesignColors.onSurface)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.notifications, color: _DesignColors.onSurface, size: 22),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: CircleAvatar(radius: 4, backgroundColor: _DesignColors.primaryContainer),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Arya Pratama', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _DesignColors.onSurface)),
                  const Text('Chief Dispatcher', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant)),
                ],
              ),
              const SizedBox(width: 8),
              const CircleAvatar(
                radius: 16,
                backgroundColor: _DesignColors.primary,
                child: Icon(Icons.person, color: _DesignColors.onPrimary, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _DesignColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: _DesignColors.primaryContainer.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.tune, color: _DesignColors.primaryContainer, size: 20),
                  ),
                  const SizedBox(width: 8),
                  const Text('Workshop Capacity & Operating Calendar', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _DesignColors.onSurface)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: _DesignColors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: _DesignColors.emerald500, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('ENGINE SYNCED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurface, letterSpacing: 1.2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Configure simultaneous throughput and blackout dates for Revive Hub Kebon Jeruk. AI auto-dispatch respects dynamic panel ceilings and partner blackout windows.',
            style: TextStyle(fontSize: 14, color: _DesignColors.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaWidgets() {
    return Row(
      children: [
        Expanded(child: _buildQuotaCard('Simultaneous Intake', Icons.speed, _DesignColors.primaryContainer, _intakeQuota, 'Panels/Day', 40, (val) => setState(() => _intakeQuota = val))),
        const SizedBox(width: 16),
        Expanded(child: _buildQuotaCard('Insurer Guarantee', Icons.verified_user, _DesignColors.secondaryContainer, _insurerQuota, 'Slots/Day', 12, (val) => setState(() => _insurerQuota = val))),
        const SizedBox(width: 16),
        Expanded(child: _buildFastTrackCard()),
      ],
    );
  }

  Widget _buildQuotaCard(String title, IconData icon, Color color, int value, String unit, int max, Function(int) onChanged) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _DesignColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant, letterSpacing: 1.2)),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$value', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: _DesignColors.onSurface, height: 1)),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _DesignColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: value / max,
            backgroundColor: _DesignColors.surfaceContainerHigh,
            color: color,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _DesignColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(onTap: () => onChanged(value > 1 ? value - 1 : 1), child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: _DesignColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.remove, size: 16, color: _DesignColors.onSurface))),
                const Text('Panel Ceiling', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant)),
                InkWell(onTap: () => onChanged(value < max ? value + 1 : max), child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: _DesignColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.add, size: 16, color: _DesignColors.onSurface))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFastTrackCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _DesignColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('FAST-TRACK MODE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant, letterSpacing: 1.2)),
              const Icon(Icons.bolt, color: _DesignColors.primary, size: 18),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Express 24h', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _DesignColors.onSurface, height: 1)),
          const SizedBox(height: 8),
          const Text('Priority bypass for minor dent & spot cures', style: TextStyle(fontSize: 12, color: _DesignColors.onSurfaceVariant)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: _DesignColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_isFastTrackActive ? 'ACTIVE' : 'INACTIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _isFastTrackActive ? _DesignColors.primary : _DesignColors.onSurfaceVariant, letterSpacing: 1.2)),
                Switch(
                  value: _isFastTrackActive,
                  onChanged: (v) => setState(() => _isFastTrackActive = v),
                  activeColor: _DesignColors.primaryContainer,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _DesignColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_month, color: _DesignColors.primary, size: 22),
                  const SizedBox(width: 8),
                  const Text('September 2026', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _DesignColors.onSurface)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: _DesignColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(4)),
                    child: const Text('Peak Cycle', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant)),
                  ),
                ],
              ),
              Row(
                children: [
                  _legendItem(_DesignColors.emerald500, 'Working Day'),
                  const SizedBox(width: 16),
                  _legendItem(_DesignColors.primaryContainer, 'Day Off / Closed'),
                  const SizedBox(width: 16),
                  _legendItem(_DesignColors.secondaryContainer, 'National Holiday'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(), 1: FlexColumnWidth(), 2: FlexColumnWidth(), 3: FlexColumnWidth(),
              4: FlexColumnWidth(), 5: FlexColumnWidth(), 6: FlexColumnWidth(),
            },
            children: [
              TableRow(
                children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => 
                  Container(
                    margin: const EdgeInsets.all(4),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: _DesignColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text(d.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: d == 'Sun' ? _DesignColors.primaryContainer : _DesignColors.onSurfaceVariant))),
                  )
                ).toList(),
              ),
              _buildCalRow(
                _calDayEmpty('31'), _calDay('01', '14/18'), _calDay('02', '16/18'), _calDay('03', '12/18'), _calDay('04', '18/18'), _calDay('05', '10/18'), _calDayOff('06'),
              ),
              _buildCalRow(
                _calDay('07', '15/18'), _calDay('08', '17/18'), _calDay('09', '11/18'), _calDay('10', '13/18'), _calDay('11', '14/18'), _calDayMaint('12'), _calDayOff('13'),
              ),
              _buildCalRow(
                _calDayHoliday('14'), _calDay('15', '08/18'), _calDay('16', '14/18'), _calDay('17', '12/18'), _calDay('18', '15/18'), _calDay('19', '09/18'), _calDayOff('20'),
              ),
              _buildCalRow(
                _calDay('21', '16/18'), _calDay('22', '13/18'), _calDay('23', '14/18'), _calDay('24', '18/18'), _calDay('25', '11/18'), _calDay('26', '07/18'), _calDayClean('27'),
              ),
              _buildCalRow(
                _calDay('28', '12/18'), _calDay('29', '15/18'), _calDay('30', '13/18'), _calDayEmpty('01'), _calDayEmpty('02'), _calDayEmpty('03'), _calDayEmpty('04'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _buildCalRow(Widget a, Widget b, Widget c, Widget d, Widget e, Widget f, Widget g) {
    return TableRow(children: [a, b, c, d, e, f, g]);
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant)),
      ],
    );
  }

  Widget _calDayEmpty(String date) {
    return Container(
      height: 64, margin: const EdgeInsets.all(4), padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: _DesignColors.surfaceContainerLow.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(date, style: TextStyle(fontSize: 12, color: _DesignColors.onSurfaceVariant.withValues(alpha: 0.3))),
        Text('--', style: TextStyle(fontSize: 10, color: _DesignColors.onSurfaceVariant.withValues(alpha: 0.3))),
      ]),
    );
  }
  Widget _calDay(String date, String quota) {
    return Container(
      height: 64, margin: const EdgeInsets.all(4), padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: _DesignColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _DesignColors.onSurface)),
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: _DesignColors.emerald500, shape: BoxShape.circle)),
        ]),
        Text(quota, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant)),
      ]),
    );
  }
  Widget _calDayOff(String date) {
    return Container(
      height: 64, margin: const EdgeInsets.all(4), padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: _DesignColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _DesignColors.primary)),
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: _DesignColors.primaryContainer, shape: BoxShape.circle)),
        ]),
        const Text('OFF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _DesignColors.primary, letterSpacing: 1.2)),
      ]),
    );
  }
  Widget _calDayMaint(String date) {
    return Container(
      height: 64, margin: const EdgeInsets.all(4), padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: _DesignColors.primaryFixed.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _DesignColors.primary)),
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: _DesignColors.primaryContainer, shape: BoxShape.circle)),
        ]),
        Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(color: _DesignColors.primaryContainer, borderRadius: BorderRadius.circular(4)),
          child: const Text('MAINT.', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _DesignColors.onPrimary)),
        ),
      ]),
    );
  }
  Widget _calDayClean(String date) {
    return Container(
      height: 64, margin: const EdgeInsets.all(4), padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: _DesignColors.primaryFixed.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _DesignColors.primary)),
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: _DesignColors.primaryContainer, shape: BoxShape.circle)),
        ]),
        Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(color: _DesignColors.primaryContainer, borderRadius: BorderRadius.circular(4)),
          child: const Text('CLEAN', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _DesignColors.onPrimary)),
        ),
      ]),
    );
  }
  Widget _calDayHoliday(String date) {
    return Container(
      height: 64, margin: const EdgeInsets.all(4), padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: _DesignColors.secondaryFixed.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _DesignColors.secondary)),
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: _DesignColors.secondaryContainer, shape: BoxShape.circle)),
        ]),
        Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(color: _DesignColors.secondary, borderRadius: BorderRadius.circular(4)),
          child: const Text('HOLIDAY', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _DesignColors.onSecondary)),
        ),
      ]),
    );
  }

  Widget _buildBlacklist() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _DesignColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_busy, color: _DesignColors.primaryContainer, size: 20),
                  const SizedBox(width: 8),
                  const Text('Blacklisted & Unavailable Windows', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _DesignColors.onSurface)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: _DesignColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.add, size: 16, color: _DesignColors.onSurface),
                    const SizedBox(width: 4),
                    const Text('Add Blackout', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _DesignColors.onSurface)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _blacklistItem('Sep', '12', 'Facility Compressor Overhaul', 'Day Off', 'Scheduled air supply maintenance & bay pressure recertification', false, _DesignColors.primaryFixed, _DesignColors.primary),
          _blacklistItem('Sep', '14', 'Maulid Nabi Muhammad SAW', 'National Holiday', 'Government statutory holiday - Hub closed as per national labor matrix', true, _DesignColors.secondaryFixed, _DesignColors.secondary),
          _blacklistItem('Sep', '27', 'Quarterly Bay Deep Clean', 'Day Off', 'Intensive booth filter swap, drainage sanitization & floor scrubbing', false, _DesignColors.primaryFixed, _DesignColors.primary),
        ],
      ),
    );
  }

  Widget _blacklistItem(String month, String day, String title, String tag, String desc, bool isLocked, Color badgeColor, Color textColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _DesignColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(month, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor, height: 1)),
                    Text(day, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor, height: 1)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _DesignColors.onSurface)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(4)),
                        child: Text(tag.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(desc, style: const TextStyle(fontSize: 12, color: _DesignColors.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          if (isLocked)
            Row(children: [
              const Icon(Icons.lock, size: 16, color: _DesignColors.onSurfaceVariant),
              const SizedBox(width: 4),
              const Text('Locked', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _DesignColors.onSurfaceVariant)),
            ])
          else
            Row(children: [
              const Icon(Icons.delete, size: 16, color: _DesignColors.primary),
              const SizedBox(width: 4),
              const Text('Remove', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _DesignColors.primary)),
            ]),
        ],
      ),
    );
  }

  Widget _buildCommlink() {
    return Container(
      constraints: const BoxConstraints(minHeight: 760),
      decoration: BoxDecoration(
        color: _DesignColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        children: [
          // Commlink Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _DesignColors.surfaceContainerLowest,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1))],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: _DesignColors.primaryContainer.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.hub, color: _DesignColors.primaryContainer, size: 22),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('Revive HQ Commlink', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _DesignColors.onSurface)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: _DesignColors.primaryContainer, borderRadius: BorderRadius.circular(4)),
                                  child: const Text('PRIORITY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _DesignColors.onPrimary, letterSpacing: 1.2)),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Container(width: 8, height: 8, decoration: const BoxDecoration(color: _DesignColors.emerald500, shape: BoxShape.circle)),
                                const SizedBox(width: 4),
                                const Text('Master Dispatch Operations • Online', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.phone_in_talk, color: _DesignColors.onSurfaceVariant, size: 18),
                        const SizedBox(width: 16),
                        const Icon(Icons.verified, color: _DesignColors.onSurfaceVariant, size: 18),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _quickAction(Icons.emergency, 'Emergency Override', _DesignColors.primaryContainer),
                    const SizedBox(width: 8),
                    _quickAction(Icons.inventory_2, 'Part Catalog', _DesignColors.onSurface),
                    const SizedBox(width: 8),
                    _quickAction(Icons.warning, 'Capacity Alert', _DesignColors.secondaryContainer),
                  ],
                ),
              ],
            ),
          ),
          // Chat Stream
          Expanded(
            child: Container(
              color: _DesignColors.surfaceContainerLow.withValues(alpha: 0.4),
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(color: _DesignColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
                      child: const Text('Today, 10:14 AM WIB', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _chatBubbleLeft('HQ Senior Dispatcher (Bayu)', '10:14 AM', 'Hub 04: Alerting on high intake for Toyota & Honda front bumper panels today. Can your paint booth take 3 additional express cures this afternoon?'),
                  const SizedBox(height: 16),
                  _chatBubbleRight('You (Arya - Hub 04 Lead)', '10:16 AM', 'Confirmed HQ, Bay #02 curing cycle finishes at 14:00 WIB. We can take 3 express panels immediately after.'),
                  const SizedBox(height: 16),
                  _chatBubbleLeft('HQ Senior Dispatcher (Bayu)', '10:18 AM', 'Approved and dispatched job JB-03537083 (Toyota Innova Zenix) to your bay. Transfer proof verified.'),
                  const SizedBox(height: 16),
                  // Bento card
                  Container(
                    margin: const EdgeInsets.only(left: 44, right: 44),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _DesignColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)]),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(color: _DesignColors.emerald500.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.assignment_turned_in, color: _DesignColors.emerald500, size: 20),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Job #JB-03537083 dispatched to your queue', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _DesignColors.onSurface)),
                                const Text('2.0 V CVT • Front Bumper & Left Fender Repair', style: TextStyle(fontSize: 12, color: _DesignColors.onSurfaceVariant)),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: _DesignColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
                          child: const Text('VIEW BAY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.primary, letterSpacing: 1.2)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Message Input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _DesignColors.surfaceContainerLowest,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, -1))],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: _DesignColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.attachment, color: _DesignColors.onSurfaceVariant, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          decoration: const InputDecoration.collapsed(
                            hintText: 'Type a message to Revive Master Admin...',
                            hintStyle: TextStyle(color: _DesignColors.onSurfaceVariant, fontSize: 14),
                          ),
                        ),
                      ),
                      const Icon(Icons.sentiment_satisfied, color: _DesignColors.onSurfaceVariant, size: 20),
                      const SizedBox(width: 8),
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: _DesignColors.primaryContainer, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.send, color: _DesignColors.onPrimary, size: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock, size: 14, color: _DesignColors.onSurfaceVariant),
                        const SizedBox(width: 4),
                        const Text('Revive Commlink TLS 1.3', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant)),
                      ],
                    ),
                    const Text('Latency: 12ms', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _DesignColors.onSurfaceVariant, fontFamily: 'monospace')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction(IconData icon, String text, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: _DesignColors.surfaceContainerLow, borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _DesignColors.onSurface)),
        ],
      ),
    );
  }

  Widget _chatBubbleLeft(String name, String time, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32, height: 32,
          decoration: const BoxDecoration(color: _DesignColors.surfaceContainerHighest, shape: BoxShape.circle),
          child: const Center(child: Text('HQ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _DesignColors.onSurface))),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _DesignColors.onSurface)),
                  const SizedBox(width: 8),
                  Text(time, style: const TextStyle(fontSize: 11, color: _DesignColors.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: _DesignColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.only(topRight: Radius.circular(12), bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Text(text, style: const TextStyle(fontSize: 14, color: _DesignColors.onSurface)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 48), // limit width implicitly
      ],
    );
  }

  Widget _chatBubbleRight(String name, String time, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const SizedBox(width: 48), // limit width implicitly
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(time, style: const TextStyle(fontSize: 11, color: _DesignColors.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _DesignColors.onSurface)),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: _DesignColors.primaryContainer,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Text(text, style: const TextStyle(fontSize: 14, color: _DesignColors.onPrimary)),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.done_all, size: 14, color: _DesignColors.primary),
                  const SizedBox(width: 4),
                  const Text('Delivered', style: TextStyle(fontSize: 10, color: _DesignColors.primary)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
