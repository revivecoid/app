import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';

// ─── Data models ──────────────────────────────────────────────────────────────

class _PanelRow {
  final String id;
  final String name;
  final String baseRate;
  final String severity;
  final bool isPending;
  const _PanelRow({required this.id, required this.name, required this.baseRate, required this.severity, this.isPending = false});
}

const _panels = [
  _PanelRow(id: 'PANEL_FRONT_BUMP', name: 'Bumper Depan', baseRate: 'Rp 1.150.000', severity: '1.0x - 2.8x (Auto)'),
  _PanelRow(id: 'PANEL_HOOD_ENG', name: 'Kap Mesin (Hood)', baseRate: 'Rp 1.425.000', severity: '1.2x - 3.4x (Auto)'),
  _PanelRow(id: 'PANEL_FENDER_FR_RH', name: 'Fender Kanan Depan (RH)', baseRate: 'Rp 1.000.000', severity: '1.0x - 2.5x (Auto)'),
  _PanelRow(id: 'PANEL_DOOR_FR_RH', name: 'Pintu Kanan Depan (Door RH)', baseRate: 'Rp 1.200.000', severity: 'Review Needed', isPending: true),
  _PanelRow(id: 'PANEL_DOOR_RR_RH', name: 'Pintu Kanan Belakang (Door RH)', baseRate: 'Rp 1.200.000', severity: '1.0x - 2.5x (Auto)'),
  _PanelRow(id: 'PANEL_FENDER_RR_RH', name: 'Fender Kanan Belakang (RH)', baseRate: 'Rp 1.050.000', severity: '1.1x - 3.0x (Auto)'),
  _PanelRow(id: 'PANEL_DOOR_FR_LH', name: 'Pintu Kiri Depan (Door LH)', baseRate: 'Rp 1.200.000', severity: '1.0x - 2.5x (Auto)'),
  _PanelRow(id: 'PANEL_DOOR_RR_LH', name: 'Pintu Kiri Belakang (Door LH)', baseRate: 'Rp 1.200.000', severity: '1.0x - 2.5x (Auto)'),
  _PanelRow(id: 'PANEL_FENDER_FR_LH', name: 'Fender Kiri Depan (LH)', baseRate: 'Rp 1.000.000', severity: '1.0x - 2.5x (Auto)'),
  _PanelRow(id: 'PANEL_FENDER_RR_LH', name: 'Fender Kiri Belakang (LH)', baseRate: 'Rp 1.050.000', severity: '1.1x - 3.0x (Auto)'),
  _PanelRow(id: 'PANEL_ROOF', name: 'Atap (Roof)', baseRate: 'Rp 2.100.000', severity: '1.5x - 4.2x (Manual)', isPending: true),
  _PanelRow(id: 'PANEL_TRUNK', name: 'Bagasi / Trunk Lid', baseRate: 'Rp 1.375.000', severity: '1.2x - 3.0x (Auto)'),
  _PanelRow(id: 'PANEL_REAR_BUMP', name: 'Bumper Belakang', baseRate: 'Rp 1.150.000', severity: '1.0x - 2.8x (Auto)'),
  _PanelRow(id: 'PANEL_A_PILLAR', name: 'A-Pillar / Rocker Panel', baseRate: 'Rp 875.000', severity: '1.0x - 2.0x (Auto)'),
];

// ─── NLP Intents ──────────────────────────────────────────────────────────────
class _NlpIntent {
  final String name;
  final String description;
  final int phrases;
  final double accuracy;
  final bool active;
  const _NlpIntent({required this.name, required this.description, required this.phrases, required this.accuracy, this.active = true});
}

const _nlpIntents = [
  _NlpIntent(name: 'estimate_request', description: 'Customer requests damage cost estimate', phrases: 48, accuracy: 97.2),
  _NlpIntent(name: 'booking_schedule', description: 'Customer wants to book workshop slot', phrases: 35, accuracy: 95.8),
  _NlpIntent(name: 'track_repair_status', description: 'Query on ongoing repair progress', phrases: 27, accuracy: 98.1),
  _NlpIntent(name: 'payment_query', description: 'Questions about invoice and payment', phrases: 22, accuracy: 93.4),
  _NlpIntent(name: 'partner_escalation', description: 'Escalate to human partner agent', phrases: 15, accuracy: 91.0),
  _NlpIntent(name: 'promo_inquiry', description: 'Ask about active promotions & discounts', phrases: 19, accuracy: 89.5, active: false),
  _NlpIntent(name: 'complaint_filing', description: 'Customer filing dissatisfaction report', phrases: 31, accuracy: 96.3),
];

// ─── Commission Settlements ───────────────────────────────────────────────────
class _Settlement {
  final String partner;
  final String workshopId;
  final String amount;
  final String commission;
  final String status;
  final String date;
  const _Settlement({required this.partner, required this.workshopId, required this.amount, required this.commission, required this.status, required this.date});
}

const _settlements = [
  _Settlement(partner: 'AutoBody Prima JKT', workshopId: 'WS-JKT-001', amount: 'Rp 24.500.000', commission: 'Rp 3.675.000', status: 'paid', date: 'Sep 05, 2026'),
  _Settlement(partner: 'Bengkel Sentosa BSD', workshopId: 'WS-BSD-003', amount: 'Rp 18.200.000', commission: 'Rp 2.730.000', status: 'paid', date: 'Sep 05, 2026'),
  _Settlement(partner: 'CV Maju Kencana', workshopId: 'WS-TNG-007', amount: 'Rp 11.750.000', commission: 'Rp 1.762.500', status: 'pending', date: 'Sep 06, 2026'),
  _Settlement(partner: 'Cat & Body Pondok Indah', workshopId: 'WS-JKS-012', amount: 'Rp 31.000.000', commission: 'Rp 4.650.000', status: 'processing', date: 'Sep 06, 2026'),
  _Settlement(partner: 'Workshop Cibubur Auto', workshopId: 'WS-CBR-004', amount: 'Rp 8.900.000', commission: 'Rp 1.335.000', status: 'paid', date: 'Sep 04, 2026'),
  _Settlement(partner: 'AutoCare Bekasi', workshopId: 'WS-BKS-009', amount: 'Rp 14.300.000', commission: 'Rp 2.145.000', status: 'disputed', date: 'Sep 03, 2026'),
];

// ─── Digital Assets ───────────────────────────────────────────────────────────
class _AssetItem {
  final String name;
  final String type;
  final String size;
  final String cdn;
  final String category;
  final bool live;
  const _AssetItem({required this.name, required this.type, required this.size, required this.cdn, required this.category, this.live = true});
}

const _assetItems = [
  _AssetItem(name: 'asset_hero_crimson_glow_v2.webp', type: 'WebP', size: '84 KB', cdn: '32 PoPs', category: 'Hero'),
  _AssetItem(name: 'logo_revive_full_dark.svg', type: 'SVG', size: '12 KB', cdn: '32 PoPs', category: 'Brand'),
  _AssetItem(name: 'logo_revive_full_light.svg', type: 'SVG', size: '12 KB', cdn: '32 PoPs', category: 'Brand'),
  _AssetItem(name: 'car_blueprint_sedan_3d.png', type: 'PNG', size: '191 KB', cdn: '32 PoPs', category: 'Estimator'),
  _AssetItem(name: 'promo_lebaran_2026_banner.webp', type: 'WebP', size: '135 KB', cdn: '28 PoPs', category: 'Promo', live: false),
  _AssetItem(name: 'workshop_interior_photo_01.jpg', type: 'JPEG', size: '420 KB', cdn: '32 PoPs', category: 'Marketing'),
  _AssetItem(name: 'icon_spray_gun_animated.lottie', type: 'Lottie', size: '22 KB', cdn: '32 PoPs', category: 'Animation'),
  _AssetItem(name: 'car_blueprint_suv_3d.png', type: 'PNG', size: '210 KB', cdn: '32 PoPs', category: 'Estimator'),
];

// ─── Main Screen ──────────────────────────────────────────────────────────────

class FrontendContentStudioScreen extends ConsumerStatefulWidget {
  const FrontendContentStudioScreen({super.key});

  @override
  ConsumerState<FrontendContentStudioScreen> createState() => _State();
}

class _State extends ConsumerState<FrontendContentStudioScreen> {
  int _subNavIndex = 0;
  int _filterIndex = 0;
  bool _broadcastEnabled = true;
  bool _heroEnabled = true;
  bool _notifyToast = true;
  bool _redBar = true;
  // DAM state
  String _assetCategory = 'All';
  // NLP state
  final Map<int, bool> _nlpToggles = {for (var i = 0; i < _nlpIntents.length; i++) i: _nlpIntents[i].active};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(children: [
        _CmsHeader(cs: cs, isDark: isDark, ref: ref, subNavIndex: _subNavIndex, onSubNav: (i) => setState(() => _subNavIndex = i)),
        Expanded(child: _buildTabContent(cs, isDark)),
      ]),
    );
  }

  Widget _buildTabContent(ColorScheme cs, bool isDark) {
    switch (_subNavIndex) {
      case 0:
        return _ContentStudioTab(
          cs: cs,
          filterIndex: _filterIndex,
          onFilter: (i) => setState(() => _filterIndex = i),
          heroEnabled: _heroEnabled,
          broadcastEnabled: _broadcastEnabled,
          notifyToast: _notifyToast,
          redBar: _redBar,
          onHeroToggle: (v) => setState(() => _heroEnabled = v),
          onBroadcastToggle: (v) => setState(() => _broadcastEnabled = v),
          onToastToggle: (v) => setState(() => _notifyToast = v),
          onRedBarToggle: (v) => setState(() => _redBar = v),
        );
      case 1:
        return _DigitalAssetTab(cs: cs, selectedCategory: _assetCategory, onCategory: (c) => setState(() => _assetCategory = c));
      case 2:
        return _AiDamageTab(cs: cs);
      case 3:
        return _NlpStudioTab(cs: cs, toggles: _nlpToggles, onToggle: (i, v) => setState(() => _nlpToggles[i] = v));
      case 4:
        return _CommissionTab(cs: cs);
      default:
        return const SizedBox();
    }
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _CmsHeader extends StatelessWidget {
  final ColorScheme cs;
  final bool isDark;
  final WidgetRef ref;
  final int subNavIndex;
  final ValueChanged<int> onSubNav;
  const _CmsHeader({required this.cs, required this.isDark, required this.ref, required this.subNavIndex, required this.onSubNav});

  static const _tabIcons = [
    Icons.dashboard_customize_outlined,
    Icons.folder_special_outlined,
    Icons.rule_outlined,
    Icons.smart_toy_outlined,
    Icons.payments_outlined,
  ];
  static const _tabLabels = [
    'Content Studio (Landing & Mobile App)',
    'Digital Asset Manager (Edge CDN)',
    'AI Damage & Pricing Rules',
    'Customer Concierge NLP',
    'Partner Commission & Settlement',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cs.surfaceContainerLowest,
      child: Column(children: [
        // Upper row
        Container(
          height: 64, padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.surfaceContainerHigh, width: 0.5))),
          child: Row(children: [
            Icon(Icons.shield_rounded, color: cs.primary, size: 26),
            const SizedBox(width: 8),
            Text('REVIVE', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.5)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('/', style: TextStyle(color: cs.onSurfaceVariant))),
            Text('Revive Ops Core', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('/', style: TextStyle(color: cs.onSurfaceVariant))),
            Text('CMS Studio', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(width: 20),
            Expanded(child: Container(
              height: 36, padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.surfaceContainerHigh)),
              child: Row(children: [
                Icon(Icons.search_rounded, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text('Press / to search content, rules, assets...', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(4), border: Border.all(color: cs.outline.withValues(alpha: 0.3))), child: Text('/', style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: cs.onSurfaceVariant))),
              ]),
            )),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(20), border: Border.all(color: cs.surfaceContainerHigh)),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('PROD CDN: SYNCED (V4.2.1-LIVE)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurface, letterSpacing: 0.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Stack(children: [
              IconButton(icon: Icon(Icons.notifications_outlined, color: cs.onSurface, size: 22), onPressed: () {}),
              Positioned(top: 8, right: 8, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle, border: Border.all(color: cs.surfaceContainerLowest, width: 1.5)))),
            ]),
            IconButton(icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: cs.onSurface, size: 22), onPressed: () => ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark),
            const SizedBox(width: 8),
            Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Arya Pratama', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
                Text('Lead Content & Ops Admin', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ]),
              const SizedBox(width: 8),
              Container(width: 32, height: 32, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle), child: Center(child: Text('AP', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700, fontSize: 11)))),
            ]),
          ]),
        ),
        // Sub-nav tabs
        Container(
          height: 44, padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.surfaceContainerHigh, width: 0.5))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: List.generate(_tabIcons.length, (i) {
              final active = i == subNavIndex;
              return InkWell(
                onTap: () => onSubNav(i),
                child: Container(
                  margin: const EdgeInsets.only(right: 24),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: active ? cs.primary : Colors.transparent, width: 2))),
                  alignment: Alignment.center,
                  child: Row(children: [
                    Icon(_tabIcons[i], size: 15, color: active ? cs.primary : cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(_tabLabels[i], style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? cs.onSurface : cs.onSurfaceVariant)),
                  ]),
                ),
              );
            })),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 0 — CONTENT STUDIO
// ═══════════════════════════════════════════════════════════════════════════════

class _ContentStudioTab extends StatelessWidget {
  final ColorScheme cs;
  final int filterIndex;
  final ValueChanged<int> onFilter;
  final bool heroEnabled, broadcastEnabled, notifyToast, redBar;
  final ValueChanged<bool> onHeroToggle, onBroadcastToggle, onToastToggle, onRedBarToggle;
  const _ContentStudioTab({required this.cs, required this.filterIndex, required this.onFilter, required this.heroEnabled, required this.broadcastEnabled, required this.notifyToast, required this.redBar, required this.onHeroToggle, required this.onBroadcastToggle, required this.onToastToggle, required this.onRedBarToggle});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ActionBanner(cs: cs),
        const SizedBox(height: 16),
        _FilterBar(cs: cs, filterIndex: filterIndex, onFilter: onFilter),
        const SizedBox(height: 24),
        LayoutBuilder(builder: (ctx, constraints) {
          final wide = constraints.maxWidth > 900;
          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 7, child: _LeftColumn(cs: cs, heroEnabled: heroEnabled, broadcastEnabled: broadcastEnabled, notifyToast: notifyToast, redBar: redBar, onHeroToggle: onHeroToggle, onBroadcastToggle: onBroadcastToggle, onToastToggle: onToastToggle, onRedBarToggle: onRedBarToggle)),
              const SizedBox(width: 32),
              Expanded(flex: 5, child: _RightColumn(cs: cs)),
            ]);
          } else {
            return Column(children: [
              _LeftColumn(cs: cs, heroEnabled: heroEnabled, broadcastEnabled: broadcastEnabled, notifyToast: notifyToast, redBar: redBar, onHeroToggle: onHeroToggle, onBroadcastToggle: onBroadcastToggle, onToastToggle: onToastToggle, onRedBarToggle: onRedBarToggle),
              const SizedBox(height: 24),
              _RightColumn(cs: cs),
            ]);
          }
        }),
      ]),
    );
  }
}

// ─── Action Banner ────────────────────────────────────────────────────────────

class _ActionBanner extends StatelessWidget {
  final ColorScheme cs;
  const _ActionBanner({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh), boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.1), blurRadius: 16)]),
      child: LayoutBuilder(builder: (ctx, constraints) {
        final wide = constraints.maxWidth > 700;
        final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('CORE ENGINE CMS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary, fontFamily: 'monospace', letterSpacing: 1.0)),
            Text(' / REVIVE REPAIR NETWORK / ', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant, fontFamily: 'monospace')),
            Text('CLUSTER ID: JKT-EDGE-01', style: TextStyle(fontSize: 10, color: cs.onSurface, fontFamily: 'monospace')),
          ]),
          const SizedBox(height: 8),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 6, children: [
            Text('Frontend Content Studio & Digital Asset Manager', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface)),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(20), border: Border.all(color: cs.outline.withValues(alpha: 0.3))), child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 5), decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle)),
              Text('Production (v4.2.1-live)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A), letterSpacing: 0.5)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: cs.primary.withValues(alpha: 0.3))), child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.edit_document, size: 12, color: cs.primary),
              const SizedBox(width: 4),
              Text('Draft Changes (3 Unsaved)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary, letterSpacing: 0.5)),
            ])),
          ]),
        ]);
        final actions = Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          OutlinedButton.icon(onPressed: () {}, icon: Icon(Icons.history_rounded, size: 16, color: cs.onSurface), label: Text('Revert to v4.2.0', style: TextStyle(fontSize: 13, color: cs.onSurface)), style: OutlinedButton.styleFrom(side: BorderSide(color: cs.surfaceContainerHigh), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
          OutlinedButton.icon(onPressed: () {}, icon: Icon(Icons.close_rounded, size: 16, color: cs.onSurface), label: Text('Discard Changes', style: TextStyle(fontSize: 13, color: cs.onSurface)), style: OutlinedButton.styleFrom(side: BorderSide(color: cs.surfaceContainerHigh), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
          ElevatedButton.icon(onPressed: () {}, icon: Icon(Icons.cloud_sync_rounded, size: 16, color: cs.onPrimary), label: Text('Publish to Live CDN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onPrimary)), style: ElevatedButton.styleFrom(backgroundColor: cs.primary, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 4)),
        ]);
        if (wide) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: info), const SizedBox(width: 16), actions]);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(height: 12), actions]);
      }),
    );
  }
}

// ─── Filter Bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final ColorScheme cs;
  final int filterIndex;
  final ValueChanged<int> onFilter;
  const _FilterBar({required this.cs, required this.filterIndex, required this.onFilter});

  static const _filterIcons = [
    Icons.tab_outlined,
    Icons.calculate_outlined,
    Icons.campaign_outlined,
    Icons.translate_rounded,
  ];
  static const _filterLabels = [
    'Landing & Mobile App Content',
    'AI Damage Pricing Matrix (14 Panels)',
    'Promotional Banners & Popups',
    'Localization (ID / EN)',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.surfaceContainerHigh)),
      child: Row(children: [
        Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: List.generate(_filterIcons.length, (i) {
          final active = i == filterIndex;
          return GestureDetector(
            onTap: () => onFilter(i),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: active ? cs.surfaceContainerHigh : Colors.transparent, borderRadius: BorderRadius.circular(6), border: active ? Border.all(color: cs.surfaceContainerHigh) : null),
              child: Row(children: [
                Icon(_filterIcons[i], size: 15, color: active ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(_filterLabels[i], style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? cs.onSurface : cs.onSurfaceVariant)),
              ]),
            ),
          );
        })))),
        Row(children: [
          Icon(Icons.verified_user_outlined, size: 15, color: const Color(0xFF16A34A)),
          const SizedBox(width: 6),
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Strict Schema Guard: ', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            TextSpan(text: 'Active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
          ])),
        ]),
        const SizedBox(width: 8),
      ]),
    );
  }
}
// ─── Left Column ──────────────────────────────────────────────────────────────

class _LeftColumn extends StatelessWidget {
  final ColorScheme cs;
  final bool heroEnabled, broadcastEnabled, notifyToast, redBar;
  final ValueChanged<bool> onHeroToggle, onBroadcastToggle, onToastToggle, onRedBarToggle;
  const _LeftColumn({required this.cs, required this.heroEnabled, required this.broadcastEnabled, required this.notifyToast, required this.redBar, required this.onHeroToggle, required this.onBroadcastToggle, required this.onToastToggle, required this.onRedBarToggle});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Section jump pills
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        Text('Section Jump:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 0.5)),
        const SizedBox(width: 8),
        _Pill(cs: cs, label: 'All Sections', active: true),
        _Pill(cs: cs, label: 'Hero Value Prop'),
        _Pill(cs: cs, label: 'Active Repair Banner'),
        _Pill(cs: cs, label: '4-Step Intake Flow'),
        _Pill(cs: cs, label: 'Trust Badges'),
        _Pill(cs: cs, label: 'Footer FAQs'),
      ])),
      const SizedBox(height: 20),
      _Module01(cs: cs, enabled: heroEnabled, onToggle: onHeroToggle),
      const SizedBox(height: 20),
      _Module02(cs: cs),
      const SizedBox(height: 20),
      _Module03(cs: cs, enabled: broadcastEnabled, onToggle: onBroadcastToggle, notifyToast: notifyToast, onToastToggle: onToastToggle, redBar: redBar, onRedBarToggle: onRedBarToggle),
    ]);
  }
}

// ─── Module 01: Hero Section ──────────────────────────────────────────────────

class _Module01 extends StatelessWidget {
  final ColorScheme cs;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  const _Module01({required this.cs, required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return _ModuleCard(
      cs: cs,
      num: '01',
      title: 'Hero Section & Value Proposition',
      subtitle: 'Target: Landing Page Hero & App Dynamic Welcome Modal',
      statusLabel: 'PUBLISHED - LIVE',
      statusColor: const Color(0xFF16A34A),
      enabled: enabled,
      onToggle: onToggle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Label(cs: cs, text: 'Headline (H1 Title)'),
        _FieldRow(cs: cs, value: 'Body Repair Made Simple.', trailing: Icon(Icons.verified_rounded, color: const Color(0xFF16A34A), size: 18)),
        const SizedBox(height: 12),
        _Label(cs: cs, text: 'Sub-Headline Narrative'),
        _TextArea(cs: cs, value: 'Instant body repair estimation & real-time tracking. Get your car shining faster, with absolute transparency.'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Label(cs: cs, text: 'Primary CTA Label'),
            _FieldRow(cs: cs, value: 'Get Free AI Estimate'),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Label(cs: cs, text: 'Target Route / Deep Link'),
            _FieldRow(cs: cs, value: 'app://estimator?source=hero', mono: true, leading: Icon(Icons.link_rounded, size: 15, color: cs.tertiary)),
          ])),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.outline.withValues(alpha: 0.2))),
          child: Row(children: [
            Container(width: 56, height: 44, decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(6), border: Border.all(color: cs.surfaceContainerHigh)), child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant, size: 24))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('asset_hero_crimson_glow_v2.webp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
              Text('WebP Optimized (84 KB) - Edge Cached Worldwide', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ])),
            OutlinedButton.icon(onPressed: () {}, icon: Icon(Icons.image_outlined, size: 14, color: cs.onSurface), label: Text('Replace', style: TextStyle(fontSize: 12, color: cs.onSurface)), style: OutlinedButton.styleFrom(side: BorderSide(color: cs.surfaceContainerHigh), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap)),
          ]),
        ),
      ]),
    );
  }
}

// ─── Module 02: Pricing Matrix ────────────────────────────────────────────────

class _Module02 extends StatelessWidget {
  final ColorScheme cs;
  const _Module02({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh), boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.08), blurRadius: 12)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _NumBadge(cs: cs, num: '02'),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI Damage Estimator Panel Pricing & Severity Rules', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 2),
            Text('Configured live computational multiplier per vehicle panel', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ])),
          const SizedBox(width: 8),
          Wrap(spacing: 8, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: cs.tertiary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: cs.tertiary.withValues(alpha: 0.3))), child: Text('AI MODEL v2.4 SYNCED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.tertiary, letterSpacing: 0.5))),
            OutlinedButton.icon(onPressed: () {}, icon: Icon(Icons.download_rounded, size: 14, color: cs.onSurface), label: Text('Bulk Export JSON', style: TextStyle(fontSize: 11, color: cs.onSurface)), style: OutlinedButton.styleFrom(side: BorderSide(color: cs.surfaceContainerHigh), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)))),
            ElevatedButton.icon(onPressed: () {}, icon: Icon(Icons.add_rounded, size: 14, color: cs.onPrimary), label: Text('Add Panel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onPrimary)), style: ElevatedButton.styleFrom(backgroundColor: cs.primary, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)))),
          ]),
        ]),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Table(
            border: TableBorder.all(color: cs.surfaceContainerHigh, width: 0.8),
            columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2), 3: FlexColumnWidth(1.5), 4: FixedColumnWidth(48)},
            children: [
              TableRow(decoration: BoxDecoration(color: cs.surfaceContainerHigh), children: [
                _THead(cs: cs, text: 'Panel ID & Location'),
                _THead(cs: cs, text: 'Base Paint & Dent Rate'),
                _THead(cs: cs, text: 'Severity Scale'),
                _THead(cs: cs, text: 'Status'),
                _THead(cs: cs, text: ''),
              ]),
              ..._panels.take(4).toList().asMap().entries.map((e) {
                final row = e.value;
                final alt = e.key.isOdd;
                return TableRow(decoration: BoxDecoration(color: alt ? cs.surfaceContainer : cs.surface), children: [
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(row.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
                      Text('(${row.id})', style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.onSurfaceVariant)),
                    ])),
                  ])),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text(row.baseRate, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface, fontFamily: 'monospace'))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: row.isPending ? cs.secondaryContainer.withValues(alpha: 0.2) : cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4), border: Border.all(color: row.isPending ? cs.onSurfaceVariant.withValues(alpha: 0.2) : cs.primary.withValues(alpha: 0.25))), child: Text(row.severity, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: row.isPending ? cs.onSurfaceVariant : cs.primary)))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: row.isPending ? cs.secondary : const Color(0xFF16A34A), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Expanded(child: Text(row.isPending ? 'Pending' : 'Live', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: row.isPending ? cs.secondary : const Color(0xFF16A34A)))),
                  ])),
                  Padding(padding: const EdgeInsets.all(4), child: IconButton(icon: Icon(Icons.tune_rounded, size: 18, color: cs.onSurfaceVariant), onPressed: () {}, padding: EdgeInsets.zero, constraints: const BoxConstraints())),
                ]);
              }),
            ],
          ),
        ),
      ]),
    );
  }
}
// ─── Module 03: Broadcast Banner ─────────────────────────────────────────────

class _Module03 extends StatelessWidget {
  final ColorScheme cs;
  final bool enabled, notifyToast, redBar;
  final ValueChanged<bool> onToggle, onToastToggle, onRedBarToggle;
  const _Module03({required this.cs, required this.enabled, required this.onToggle, required this.notifyToast, required this.onToastToggle, required this.redBar, required this.onRedBarToggle});
  @override
  Widget build(BuildContext context) {
    return _ModuleCard(
      cs: cs, num: '03',
      title: 'Emergency Workshop Broadcast & Holiday Banner',
      subtitle: 'Global app top-bar notice overlay for sudden schedule adjustments',
      statusLabel: 'URGENT OVERRIDE',
      statusColor: cs.primary,
      enabled: enabled, onToggle: onToggle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Label(cs: cs, text: 'Broadcast Alert Title'),
        _FieldRow(cs: cs, value: 'Maulid Nabi National Holiday Workshop Notice', trailing: Icon(Icons.warning_rounded, color: cs.secondary, size: 20)),
        const SizedBox(height: 12),
        _Label(cs: cs, text: 'Broadcast Copy (Markdown Supported)'),
        _TextArea(cs: cs, value: 'Revive Certified Body Centers will operate on emergency towing and drop-off schedule on Sept 16. Regular paint booth cycles resume Sept 17, 08:00 WIB.'),
        const SizedBox(height: 12),
        Wrap(spacing: 24, runSpacing: 8, children: [
          _CheckRow(cs: cs, value: redBar, onChanged: onRedBarToggle, label: 'Display Red Pulsing Warning Bar at App Top Edge'),
          _CheckRow(cs: cs, value: notifyToast, onChanged: onToastToggle, label: 'Push Instant In-App Toast to 4,820 Active Customers'),
        ]),
      ]),
    );
  }
}

// ─── Right Column ─────────────────────────────────────────────────────────────

class _RightColumn extends StatelessWidget {
  final ColorScheme cs;
  const _RightColumn({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
        child: Row(children: [
          Icon(Icons.phone_iphone_rounded, color: cs.primary, size: 20),
          const SizedBox(width: 8),
          Text('Live Mobile Sync', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const Spacer(),
          Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.surfaceContainerHigh)), child: Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(6), border: Border.all(color: cs.outline.withValues(alpha: 0.2))), child: Text('iOS 17', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface))),
            const SizedBox(width: 4),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: Text('Android 14', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))),
          ])),
          const SizedBox(width: 8),
          IconButton(icon: Icon(Icons.sync_rounded, size: 18, color: cs.onSurfaceVariant), onPressed: () {}, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ]),
      ),
      const SizedBox(height: 16),
      // Phone mockup
      _PhoneMockup(cs: cs),
      const SizedBox(height: 16),
      // Telemetry card
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh), boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.08), blurRadius: 12)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.dns_rounded, color: const Color(0xFF16A34A), size: 18),
            const SizedBox(width: 8),
            Text('Global Edge Distribution', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const Spacer(),
            Text('32 Points of Presence', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.surfaceContainerHigh)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Last Synced', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('Today, 11:28 WIB', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
            ]))),
            const SizedBox(width: 12),
            Expanded(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.surfaceContainerHigh)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Edge Cache Hit Rate', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('99.8% Cached', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
            ]))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text.rich(TextSpan(children: [
              TextSpan(text: 'Release Channel: ', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              TextSpan(text: '2026.09-RC3', style: TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w700, color: cs.onSurface)),
            ]))),
            TextButton.icon(onPressed: () {}, icon: Icon(Icons.open_in_new_rounded, size: 13, color: cs.primary), label: Text('View Cloudflare Logs', style: TextStyle(fontSize: 12, color: cs.primary)), style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap)),
          ]),
        ]),
      ),
    ]);
  }
}
// ─── Phone Mockup ─────────────────────────────────────────────────────────────

class _PhoneMockup extends StatelessWidget {
  final ColorScheme cs;
  const _PhoneMockup({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(child: Container(
      width: 280, height: 560,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: cs.surfaceContainerHigh, width: 2),
        boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 12))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(38),
        child: Column(children: [
          // Dynamic island
          Container(height: 28, alignment: Alignment.center, child: Container(width: 80, height: 18, decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(20)))),
          // Scrollable content
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            physics: const NeverScrollableScrollPhysics(),
            child: Column(children: [
              // Broadcast banner
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.primary.withValues(alpha: 0.3))),
                child: Row(children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Maulid Holiday Schedule Notice', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary))),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(3)), child: Text('#Mod 03', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: cs.onPrimary))),
                ]),
              ),
              // App header
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
                Container(width: 22, height: 22, decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(6)), child: Center(child: Text('R', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w900, fontSize: 11)))),
                const SizedBox(width: 6),
                Text('REVIVE APP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: 0.5)),
                const Spacer(),
                Icon(Icons.notifications_outlined, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Container(width: 20, height: 20, decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle), child: Center(child: Text('AP', style: TextStyle(fontSize: 8, color: cs.onSurface)))),
              ])),
              const SizedBox(height: 8),
              // Hero card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('AI DIAGNOSTICS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.primary, letterSpacing: 0.8)),
                    const Spacer(),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(3)), child: Text('#Mod 01', style: TextStyle(fontSize: 8, fontFamily: 'monospace', color: cs.onSurfaceVariant))),
                  ]),
                  const SizedBox(height: 4),
                  Text('Body Repair Made Simple.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.onSurface)),
                  const SizedBox(height: 4),
                  Text('Instant body repair estimation & real-time tracking with absolute transparency.', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant, height: 1.4)),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: Container(padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(8)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Get Free AI Estimate', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onPrimary)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 12, color: cs.onPrimary),
                  ]))),
                ]),
              ),
              const SizedBox(height: 8),
              // Active repair card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('ACTIVE REPAIR TELEMETRY', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 0.5)),
                    const Spacer(),
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('In Paint Booth', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Container(width: 36, height: 36, decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.outline.withValues(alpha: 0.2))), child: Icon(Icons.directions_car_rounded, color: cs.onSurfaceVariant, size: 20)),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Toyota Innova Zenix', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)),
                      Text('B 1984 REV - Est. Friday 16:00', style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
                    ])),
                  ]),
                  const SizedBox(height: 8),
                  ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: 0.78, backgroundColor: cs.surfaceContainerHigh, valueColor: AlwaysStoppedAnimation<Color>(cs.primary), minHeight: 5)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text('Phase 4: Primer & Basecoat', style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
                    const Spacer(),
                    Text('78% Done', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  ]),
                ]),
              ),
              const SizedBox(height: 8),
              // Quick estimate tiers
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('QUICK ESTIMATE TIERS', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 0.5)),
                    const Spacer(),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(3)), child: Text('#Mod 02', style: TextStyle(fontSize: 8, fontFamily: 'monospace', color: cs.onSurfaceVariant))),
                  ]),
                  const SizedBox(height: 6),
                  ...['Bumper Depan   Rp 1.150.000', 'Kap Mesin (Hood)   Rp 1.425.000', 'Fender Kanan (RH)   Rp 1.000.000'].map((s) {
                    final parts = s.split('   ');
                    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: cs.surfaceContainerHigh)),
                      child: Row(children: [
                        Expanded(child: Text(parts[0], style: TextStyle(fontSize: 9, color: cs.onSurface))),
                        Text(parts[1], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.primary, fontFamily: 'monospace')),
                      ]),
                    ));
                  }),
                ]),
              ),
              const SizedBox(height: 12),
              // Bottom nav
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.home_rounded, size: 13, color: cs.primary),
                  const SizedBox(width: 4),
                  Text('Home', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary)),
                ]))),
                const SizedBox(width: 4),
                Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.auto_fix_high_outlined, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Estimate', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                ]))),
                const SizedBox(width: 4),
                Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.location_on_outlined, size: 13, color: cs.tertiary),
                  const SizedBox(width: 4),
                  Text('Track Status', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurface)),
                ]))),
              ]),
            ]),
          )),
          // Home bar
          Container(height: 24, alignment: Alignment.center, child: Container(width: 80, height: 4, decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(2)))),
        ]),
      ),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — DIGITAL ASSET MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

class _DigitalAssetTab extends StatelessWidget {
  final ColorScheme cs;
  final String selectedCategory;
  final ValueChanged<String> onCategory;
  const _DigitalAssetTab({required this.cs, required this.selectedCategory, required this.onCategory});

  static const _categories = ['All', 'Hero', 'Brand', 'Estimator', 'Marketing', 'Promo', 'Animation'];

  @override
  Widget build(BuildContext context) {
    final filtered = selectedCategory == 'All' ? _assetItems : _assetItems.where((a) => a.category == selectedCategory).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('DIGITAL ASSET MANAGER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary, fontFamily: 'monospace', letterSpacing: 1.0)),
            const SizedBox(height: 6),
            Text('Edge CDN Asset Library', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text('Manage brand images, 3D blueprints, banners and animations. All assets are globally distributed across 32 PoPs.', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ])),
          const SizedBox(width: 16),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () {}, icon: Icon(Icons.refresh_rounded, size: 16, color: cs.onSurface), label: Text('Sync CDN', style: TextStyle(fontSize: 13, color: cs.onSurface)), style: OutlinedButton.styleFrom(side: BorderSide(color: cs.surfaceContainerHigh), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
            ElevatedButton.icon(onPressed: () {}, icon: Icon(Icons.upload_file_rounded, size: 16, color: cs.onPrimary), label: Text('Upload Asset', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onPrimary)), style: ElevatedButton.styleFrom(backgroundColor: cs.primary, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 4)),
          ]),
        ]),
        const SizedBox(height: 20),
        // Storage stats
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
          child: Row(children: [
            Expanded(child: _DamKpi(cs: cs, icon: Icons.folder_outlined, label: 'Total Assets', value: '${_assetItems.length} Files', sub: 'Across all categories', color: cs.primary)),
            _DamDivider(cs: cs),
            Expanded(child: _DamKpi(cs: cs, icon: Icons.storage_rounded, label: 'Storage Used', value: '1.14 GB', sub: 'of 10 GB quota (11%)', color: const Color(0xFF16A34A))),
            _DamDivider(cs: cs),
            Expanded(child: _DamKpi(cs: cs, icon: Icons.bolt_rounded, label: 'CDN Cache Rate', value: '99.8%', sub: '32 Points of Presence', color: cs.tertiary)),
            _DamDivider(cs: cs),
            Expanded(child: _DamKpi(cs: cs, icon: Icons.cloud_done_rounded, label: 'Last Full Sync', value: 'Today 11:28', sub: 'WIB — Auto Sync On', color: cs.secondary)),
          ]),
        ),
        const SizedBox(height: 20),
        // Upload drop zone
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.primary.withValues(alpha: 0.25), width: 1.5),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle), child: Icon(Icons.cloud_upload_rounded, color: cs.primary, size: 24)),
            const SizedBox(height: 10),
            Text('Drag & drop files here, or', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            TextButton(onPressed: () {}, child: Text('Browse Files', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary))),
            const SizedBox(height: 4),
            Text('Supports: WebP, SVG, PNG, JPEG, Lottie JSON  •  Max 50 MB per file', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(height: 20),
        // Category filter
        Row(children: [
          Text('Filter by Category:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          const SizedBox(width: 10),
          Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _categories.map((cat) {
            final active = cat == selectedCategory;
            return GestureDetector(
              onTap: () => onCategory(cat),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: active ? cs.primary : cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(20), border: active ? null : Border.all(color: cs.surfaceContainerHigh)),
                child: Text(cat, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w400, color: active ? cs.onPrimary : cs.onSurfaceVariant)),
              ),
            );
          }).toList()))),
          Text('${filtered.length} assets', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: 16),
        // Asset grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.82),
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final asset = filtered[i];
            return _AssetCard(cs: cs, asset: asset);
          },
        ),
      ]),
    );
  }
}

class _DamKpi extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final String label, value, sub;
  final Color color;
  const _DamKpi({required this.cs, required this.icon, required this.label, required this.value, required this.sub, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 0.3)),
      ]),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
      const SizedBox(height: 2),
      Text(sub, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
    ]);
  }
}

class _DamDivider extends StatelessWidget {
  final ColorScheme cs;
  const _DamDivider({required this.cs});
  @override
  Widget build(BuildContext context) => Container(width: 0.5, height: 48, margin: const EdgeInsets.symmetric(horizontal: 16), color: cs.surfaceContainerHigh);
}

class _AssetCard extends StatelessWidget {
  final ColorScheme cs;
  final _AssetItem asset;
  const _AssetCard({required this.cs, required this.asset});

  Color get _typeColor {
    switch (asset.type) {
      case 'WebP': return const Color(0xFF2563EB);
      case 'SVG': return const Color(0xFF7C3AED);
      case 'PNG': return const Color(0xFF059669);
      case 'JPEG': return const Color(0xFFD97706);
      case 'Lottie': return const Color(0xFFDB2777);
      default: return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(10), border: Border.all(color: cs.surfaceContainerHigh), boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.06), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Preview area
        Expanded(child: Container(
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(_getIcon(), size: 32, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: _typeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)), child: Text(asset.type, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _typeColor))),
          ])),
        )),
        // Info
        Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(asset.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            Text(asset.size, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            const Spacer(),
            Container(width: 6, height: 6, decoration: BoxDecoration(color: asset.live ? const Color(0xFF16A34A) : cs.secondary, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(asset.live ? 'Live' : 'Draft', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: asset.live ? const Color(0xFF16A34A) : cs.secondary)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.dns_rounded, size: 11, color: cs.tertiary),
            const SizedBox(width: 3),
            Text(asset.cdn, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            const Spacer(),
            InkWell(onTap: () {}, child: Icon(Icons.more_horiz_rounded, size: 16, color: cs.onSurfaceVariant)),
          ]),
        ])),
      ]),
    );
  }

  IconData _getIcon() {
    switch (asset.type) {
      case 'SVG': return Icons.polyline_outlined;
      case 'Lottie': return Icons.animation_rounded;
      case 'PNG': case 'JPEG': case 'WebP': return Icons.image_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2 — AI DAMAGE & PRICING RULES
// ═══════════════════════════════════════════════════════════════════════════════

class _AiDamageTab extends StatelessWidget {
  final ColorScheme cs;
  const _AiDamageTab({required this.cs});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI DAMAGE MODEL STUDIO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary, fontFamily: 'monospace', letterSpacing: 1.0)),
            const SizedBox(height: 6),
            Text('Damage & Pricing Rules', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text('Configure computer vision thresholds, panel base rates, and severity multipliers for the AI estimation engine.', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ])),
          const SizedBox(width: 16),
          Wrap(spacing: 8, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: cs.tertiary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.tertiary.withValues(alpha: 0.3))), child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6), decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle)),
              Text('ENGINE v2.4-YOLO-AutoDent', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.tertiary, letterSpacing: 0.5)),
            ])),
            OutlinedButton.icon(onPressed: () {}, icon: Icon(Icons.biotech_rounded, size: 16, color: cs.onSurface), label: Text('CV Sandbox', style: TextStyle(fontSize: 13, color: cs.onSurface)), style: OutlinedButton.styleFrom(side: BorderSide(color: cs.surfaceContainerHigh), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
            ElevatedButton.icon(onPressed: () {}, icon: Icon(Icons.rocket_launch_rounded, size: 16, color: cs.onPrimary), label: Text('Deploy Rules', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onPrimary)), style: ElevatedButton.styleFrom(backgroundColor: cs.primary, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 4)),
          ]),
        ]),
        const SizedBox(height: 20),
        // KPI row
        Row(children: [
          Expanded(child: _AiKpi(cs: cs, icon: Icons.camera_indoor_rounded, label: 'Vision Model', value: 'v2.4-YOLO', sub: '99.4% Accuracy', color: cs.primary)),
          const SizedBox(width: 12),
          Expanded(child: _AiKpi(cs: cs, icon: Icons.tune_rounded, label: 'Active Panels', value: '14 Panels', sub: '12 Live / 2 Review', color: const Color(0xFF16A34A))),
          const SizedBox(width: 12),
          Expanded(child: _AiKpi(cs: cs, icon: Icons.query_stats_rounded, label: 'Margin Index', value: '32.5% GM', sub: '+2.4% vs Standard', color: cs.tertiary)),
          const SizedBox(width: 12),
          Expanded(child: _AiKpi(cs: cs, icon: Icons.speed_rounded, label: 'Inference', value: '340ms', sub: 'ResNet TensorRT', color: const Color(0xFFF59E0B))),
        ]),
        const SizedBox(height: 20),
        // Confidence threshold card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.settings_input_component_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('Global Confidence Thresholds', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const Spacer(),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text('LIVE CONFIG', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary, letterSpacing: 0.5))),
            ]),
            const SizedBox(height: 16),
            _ThresholdRow(cs: cs, label: 'Dent Detection Minimum', value: 0.78, valueLabel: '78%', color: const Color(0xFF16A34A)),
            const SizedBox(height: 12),
            _ThresholdRow(cs: cs, label: 'Paint Scratch Confidence', value: 0.65, valueLabel: '65%', color: cs.tertiary),
            const SizedBox(height: 12),
            _ThresholdRow(cs: cs, label: 'Panel Segmentation Overlap', value: 0.90, valueLabel: '90% IoU', color: cs.primary),
            const SizedBox(height: 12),
            _ThresholdRow(cs: cs, label: 'Auto-Quote Approval Threshold', value: 0.85, valueLabel: '85%', color: const Color(0xFFF59E0B)),
          ]),
        ),
        const SizedBox(height: 20),
        // Full panel matrix table
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.table_chart_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('Panel Rate Editor Matrix', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const Spacer(),
              Text('${_panels.length} Panels Configured', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(width: 12),
              OutlinedButton.icon(onPressed: () {}, icon: Icon(Icons.download_rounded, size: 14, color: cs.onSurface), label: Text('Export JSON', style: TextStyle(fontSize: 11, color: cs.onSurface)), style: OutlinedButton.styleFrom(side: BorderSide(color: cs.surfaceContainerHigh), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)))),
              const SizedBox(width: 8),
              ElevatedButton.icon(onPressed: () {}, icon: Icon(Icons.add_rounded, size: 14, color: cs.onPrimary), label: Text('Add Panel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onPrimary)), style: ElevatedButton.styleFrom(backgroundColor: cs.primary, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)))),
            ]),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Table(
                border: TableBorder.all(color: cs.surfaceContainerHigh, width: 0.8),
                columnWidths: const {0: FlexColumnWidth(3.5), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2.5), 3: FlexColumnWidth(1.5), 4: FixedColumnWidth(80)},
                children: [
                  TableRow(decoration: BoxDecoration(color: cs.surfaceContainerHigh), children: [
                    _THead(cs: cs, text: 'Panel Name & ID'),
                    _THead(cs: cs, text: 'Base Rate'),
                    _THead(cs: cs, text: 'Severity Scale'),
                    _THead(cs: cs, text: 'Status'),
                    _THead(cs: cs, text: 'Actions'),
                  ]),
                  ..._panels.asMap().entries.map((e) {
                    final row = e.value;
                    final alt = e.key.isOdd;
                    return TableRow(decoration: BoxDecoration(color: alt ? cs.surfaceContainer : cs.surface), children: [
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(row.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
                        Text(row.id, style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.onSurfaceVariant)),
                      ])),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text(row.baseRate, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface, fontFamily: 'monospace'))),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: row.isPending ? cs.secondaryContainer.withValues(alpha: 0.2) : cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4), border: Border.all(color: row.isPending ? cs.onSurfaceVariant.withValues(alpha: 0.2) : cs.primary.withValues(alpha: 0.25))), child: Text(row.severity, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: row.isPending ? cs.onSurfaceVariant : cs.primary)))),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: row.isPending ? cs.secondary : const Color(0xFF16A34A), shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text(row.isPending ? 'Review' : 'Live', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: row.isPending ? cs.secondary : const Color(0xFF16A34A))),
                      ])),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton(icon: Icon(Icons.edit_outlined, size: 15, color: cs.onSurfaceVariant), onPressed: () {}, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                        const SizedBox(width: 4),
                        IconButton(icon: Icon(Icons.tune_rounded, size: 15, color: cs.primary), onPressed: () {}, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                      ])),
                    ]);
                  }),
                ],
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _AiKpi extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final String label, value, sub;
  final Color color;
  const _AiKpi({required this.cs, required this.icon, required this.label, required this.value, required this.sub, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: color),
          const Spacer(),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: 10),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface)),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class _ThresholdRow extends StatelessWidget {
  final ColorScheme cs;
  final String label, valueLabel;
  final double value;
  final Color color;
  const _ThresholdRow({required this.cs, required this.label, required this.value, required this.valueLabel, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: 220, child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurface))),
      const SizedBox(width: 16),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: value, backgroundColor: cs.surfaceContainerHigh, valueColor: AlwaysStoppedAnimation<Color>(color), minHeight: 8))),
      const SizedBox(width: 12),
      SizedBox(width: 70, child: Text(valueLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface, fontFamily: 'monospace'), textAlign: TextAlign.right)),
      const SizedBox(width: 8),
      IconButton(icon: Icon(Icons.edit_outlined, size: 14, color: cs.onSurfaceVariant), onPressed: () {}, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3 — CUSTOMER CONCIERGE NLP STUDIO
// ═══════════════════════════════════════════════════════════════════════════════

class _NlpStudioTab extends StatelessWidget {
  final ColorScheme cs;
  final Map<int, bool> toggles;
  final void Function(int, bool) onToggle;
  const _NlpStudioTab({required this.cs, required this.toggles, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final activeCount = toggles.values.where((v) => v).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CUSTOMER CONCIERGE AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary, fontFamily: 'monospace', letterSpacing: 1.0)),
            const SizedBox(height: 6),
            Text('NLP Intent Studio', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text('Manage NLP intents, training phrases, and chatbot routing rules for the AI concierge system.', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ])),
          const SizedBox(width: 16),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () {}, icon: Icon(Icons.add_rounded, size: 16, color: cs.onSurface), label: Text('Add Intent', style: TextStyle(fontSize: 13, color: cs.onSurface)), style: OutlinedButton.styleFrom(side: BorderSide(color: cs.surfaceContainerHigh), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
            ElevatedButton.icon(onPressed: () {}, icon: Icon(Icons.sync_rounded, size: 16, color: cs.onPrimary), label: Text('Sync NLP Models', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onPrimary)), style: ElevatedButton.styleFrom(backgroundColor: cs.primary, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 4)),
          ]),
        ]),
        const SizedBox(height: 20),
        // Stats row
        Row(children: [
          Expanded(child: _NlpStat(cs: cs, icon: Icons.psychology_rounded, label: 'Total Intents', value: '${_nlpIntents.length}', color: cs.primary)),
          const SizedBox(width: 12),
          Expanded(child: _NlpStat(cs: cs, icon: Icons.check_circle_rounded, label: 'Active Intents', value: '$activeCount', color: const Color(0xFF16A34A))),
          const SizedBox(width: 12),
          Expanded(child: _NlpStat(cs: cs, icon: Icons.chat_bubble_outline_rounded, label: 'Training Phrases', value: '${_nlpIntents.fold(0, (s, i) => s + i.phrases)}', color: cs.tertiary)),
          const SizedBox(width: 12),
          Expanded(child: _NlpStat(cs: cs, icon: Icons.insights_rounded, label: 'Avg Accuracy', value: '${(_nlpIntents.fold(0.0, (s, i) => s + i.accuracy) / _nlpIntents.length).toStringAsFixed(1)}%', color: const Color(0xFFF59E0B))),
        ]),
        const SizedBox(height: 20),
        // Intent list
        Container(
          decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
          child: Column(children: [
            // Table header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: const BorderRadius.vertical(top: Radius.circular(11))),
              child: Row(children: [
                Expanded(flex: 3, child: Text('INTENT NAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5))),
                Expanded(flex: 3, child: Text('DESCRIPTION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5))),
                SizedBox(width: 80, child: Text('PHRASES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5), textAlign: TextAlign.center)),
                SizedBox(width: 80, child: Text('ACCURACY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5), textAlign: TextAlign.center)),
                SizedBox(width: 60, child: Text('ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5), textAlign: TextAlign.center)),
                SizedBox(width: 40, child: Text('', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant))),
              ]),
            ),
            ..._nlpIntents.asMap().entries.map((e) {
              final idx = e.key;
              final intent = e.value;
              final active = toggles[idx] ?? intent.active;
              return Container(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.surfaceContainerHigh, width: 0.5))),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Expanded(flex: 3, child: Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: active ? const Color(0xFF16A34A) : cs.secondary, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(intent.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface, fontFamily: 'monospace'))),
                  ])),
                  Expanded(flex: 3, child: Text(intent.description, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
                  SizedBox(width: 80, child: Container(margin: const EdgeInsets.symmetric(horizontal: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)), child: Text('${intent.phrases} phrases', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.primary), textAlign: TextAlign.center))),
                  SizedBox(width: 80, child: _AccuracyBar(cs: cs, value: intent.accuracy / 100)),
                  SizedBox(width: 60, child: Center(child: Switch(value: active, onChanged: (v) => onToggle(idx, v), activeTrackColor: const Color(0xFF16A34A), thumbColor: WidgetStateProperty.all(Colors.white), trackOutlineColor: WidgetStateProperty.all(Colors.transparent)))),
                  SizedBox(width: 40, child: Center(child: IconButton(icon: Icon(Icons.edit_outlined, size: 16, color: cs.onSurfaceVariant), onPressed: () {}, padding: EdgeInsets.zero, constraints: const BoxConstraints()))),
                ]),
              );
            }),
          ]),
        ),
        const SizedBox(height: 20),
        // NLP chat simulator
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.smart_toy_rounded, color: cs.primary, size: 18),
              const SizedBox(width: 8),
              Text('Intent Classifier Simulator', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const Spacer(),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: cs.tertiary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text('LIVE INFERENCE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.tertiary, letterSpacing: 0.5))),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.surfaceContainerHigh)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('User Input:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Text('"Berapa biaya perbaikan benturan di pintu kiri saya?"', style: TextStyle(fontSize: 13, color: cs.onSurface, fontStyle: FontStyle.italic)),
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.arrow_downward_rounded, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('Classified as:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 0.5)),
                ]),
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: const Color(0xFF16A34A).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.3))), child: Row(children: [
                  Icon(Icons.psychology_rounded, color: const Color(0xFF16A34A), size: 16),
                  const SizedBox(width: 8),
                  Text('estimate_request', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A), fontFamily: 'monospace')),
                  const Spacer(),
                  Text('Confidence: 97.2%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
                ])),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _NlpStat extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final String label, value;
  final Color color;
  const _NlpStat({required this.cs, required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface)),
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ]),
      ]),
    );
  }
}

class _AccuracyBar extends StatelessWidget {
  final ColorScheme cs;
  final double value;
  const _AccuracyBar({required this.cs, required this.value});

  Color get _color {
    if (value >= 0.95) return const Color(0xFF16A34A);
    if (value >= 0.90) return const Color(0xFF2563EB);
    return const Color(0xFFF59E0B);
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text('${(value * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)),
      const SizedBox(height: 3),
      ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: value, backgroundColor: cs.surfaceContainerHigh, valueColor: AlwaysStoppedAnimation<Color>(_color), minHeight: 5)),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 4 — PARTNER COMMISSION & SETTLEMENT ENGINE
// ═══════════════════════════════════════════════════════════════════════════════

class _CommissionTab extends StatelessWidget {
  final ColorScheme cs;
  const _CommissionTab({required this.cs});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PARTNER SETTLEMENT ENGINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary, fontFamily: 'monospace', letterSpacing: 1.0)),
            const SizedBox(height: 6),
            Text('Commission & Payout Ledger', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text('Automated workshop payouts, commission reconciliation, and margin index reporting.', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ])),
          const SizedBox(width: 16),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () {}, icon: Icon(Icons.download_rounded, size: 16, color: cs.onSurface), label: Text('Export Report', style: TextStyle(fontSize: 13, color: cs.onSurface)), style: OutlinedButton.styleFrom(side: BorderSide(color: cs.surfaceContainerHigh), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
            ElevatedButton.icon(onPressed: () {}, icon: Icon(Icons.calculate_rounded, size: 16, color: cs.onPrimary), label: Text('Run Settlement Batch', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onPrimary)), style: ElevatedButton.styleFrom(backgroundColor: cs.primary, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 4)),
          ]),
        ]),
        const SizedBox(height: 20),
        // Summary tiles
        Row(children: [
          Expanded(child: _CommKpi(cs: cs, icon: Icons.check_circle_rounded, label: 'Total Paid', value: 'Rp 51.975.000', sub: '3 settlements cleared', color: const Color(0xFF16A34A))),
          const SizedBox(width: 12),
          Expanded(child: _CommKpi(cs: cs, icon: Icons.hourglass_top_rounded, label: 'Pending', value: 'Rp 1.762.500', sub: '1 batch processing', color: const Color(0xFFF59E0B))),
          const SizedBox(width: 12),
          Expanded(child: _CommKpi(cs: cs, icon: Icons.sync_rounded, label: 'Processing', value: 'Rp 4.650.000', sub: '1 in reconciliation', color: cs.tertiary)),
          const SizedBox(width: 12),
          Expanded(child: _CommKpi(cs: cs, icon: Icons.warning_rounded, label: 'Disputed', value: 'Rp 2.145.000', sub: '1 needs review', color: cs.primary)),
        ]),
        const SizedBox(height: 20),
        // Commission config card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.percent_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('Commission Rate Configuration', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const Spacer(),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text('GLOBAL DEFAULTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary, letterSpacing: 0.5))),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _CommConfigRow(cs: cs, label: 'Standard Workshop Commission', value: '15.0%')),
              const SizedBox(width: 24),
              Expanded(child: _CommConfigRow(cs: cs, label: 'Premium Partner Commission', value: '12.5%')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _CommConfigRow(cs: cs, label: 'Platform Transaction Fee', value: '2.5%')),
              const SizedBox(width: 24),
              Expanded(child: _CommConfigRow(cs: cs, label: 'Insurance Claim Markup', value: '8.0%')),
            ]),
          ]),
        ),
        const SizedBox(height: 20),
        // Settlement ledger table
        Container(
          decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.all(16), child: Row(children: [
              Icon(Icons.receipt_long_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('Settlement Ledger', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const Spacer(),
              Text('${_settlements.length} transactions — Sep 2026', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ])),
            Container(height: 0.5, color: cs.surfaceContainerHigh),
            // Headers
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: cs.surfaceContainerHigh,
              child: Row(children: [
                Expanded(flex: 3, child: Text('PARTNER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('WORKSHOP ID', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('JOB REVENUE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('COMMISSION (15%)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5))),
                Expanded(flex: 1, child: Text('STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5))),
                Expanded(flex: 1, child: Text('DATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5))),
                SizedBox(width: 40, child: Text('', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant))),
              ]),
            ),
            ..._settlements.asMap().entries.map((e) {
              final alt = e.key.isOdd;
              final s = e.value;
              final (statusColor, statusBg) = _statusColors(cs, s.status);
              return Container(
                color: alt ? cs.surfaceContainer : null,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Expanded(flex: 3, child: Text(s.partner, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface))),
                  Expanded(flex: 2, child: Text(s.workshopId, style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurfaceVariant))),
                  Expanded(flex: 2, child: Text(s.amount, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface, fontFamily: 'monospace'))),
                  Expanded(flex: 2, child: Text(s.commission, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary, fontFamily: 'monospace'))),
                  Expanded(flex: 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)), child: Text(s.status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)))),
                  Expanded(flex: 1, child: Text(s.date, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))),
                  SizedBox(width: 40, child: IconButton(icon: Icon(Icons.more_vert_rounded, size: 16, color: cs.onSurfaceVariant), onPressed: () {}, padding: EdgeInsets.zero, constraints: const BoxConstraints())),
                ]),
              );
            }),
          ]),
        ),
      ]),
    );
  }

  (Color, Color) _statusColors(ColorScheme cs, String status) {
    switch (status) {
      case 'paid': return (const Color(0xFF16A34A), const Color(0xFF16A34A).withValues(alpha: 0.12));
      case 'pending': return (const Color(0xFFF59E0B), const Color(0xFFF59E0B).withValues(alpha: 0.12));
      case 'processing': return (cs.tertiary, cs.tertiary.withValues(alpha: 0.12));
      case 'disputed': return (cs.primary, cs.primary.withValues(alpha: 0.12));
      default: return (cs.onSurfaceVariant, cs.surfaceContainerHigh);
    }
  }
}

class _CommKpi extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final String label, value, sub;
  final Color color;
  const _CommKpi({required this.cs, required this.icon, required this.label, required this.value, required this.sub, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh)),
      child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 0.3)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ])),
      ]),
    );
  }
}

class _CommConfigRow extends StatelessWidget {
  final ColorScheme cs;
  final String label, value;
  const _CommConfigRow({required this.cs, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.surfaceContainerHigh)),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cs.primary, fontFamily: 'monospace')),
        const SizedBox(width: 8),
        Icon(Icons.edit_outlined, size: 14, color: cs.onSurfaceVariant),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED MODULE CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _ModuleCard extends StatelessWidget {
  final ColorScheme cs;
  final String num, title, subtitle, statusLabel;
  final Color statusColor;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final Widget child;
  const _ModuleCard({required this.cs, required this.num, required this.title, required this.subtitle, required this.statusLabel, required this.statusColor, required this.enabled, required this.onToggle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surfaceContainerHigh), boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.08), blurRadius: 12)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _NumBadge(cs: cs, num: num),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ])),
          const SizedBox(width: 12),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4), border: Border.all(color: statusColor.withValues(alpha: 0.3))), child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor, letterSpacing: 0.5))),
          const SizedBox(width: 10),
          Switch(value: enabled, activeThumbColor: cs.onPrimary, activeTrackColor: cs.primary, onChanged: onToggle),
        ]),
        const SizedBox(height: 16),
        Container(height: 0.5, color: cs.surfaceContainerHigh),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }
}

// ─── Shared Micro-widgets ─────────────────────────────────────────────────────

class _NumBadge extends StatelessWidget {
  final ColorScheme cs;
  final String num;
  const _NumBadge({required this.cs, required this.num});

  @override
  Widget build(BuildContext context) => Container(width: 32, height: 32, decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.outline.withValues(alpha: 0.2))), alignment: Alignment.center, child: Text(num, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary)));
}

class _Label extends StatelessWidget {
  final ColorScheme cs;
  final String text;
  const _Label({required this.cs, required this.text});

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.8)));
}

class _FieldRow extends StatelessWidget {
  final ColorScheme cs;
  final String value;
  final bool mono;
  final Widget? trailing, leading;
  const _FieldRow({required this.cs, required this.value, this.mono = false, this.trailing, this.leading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.surfaceContainerHigh)),
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 6)],
        Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: mono ? cs.tertiary : cs.onSurface, fontFamily: mono ? 'monospace' : null))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class _TextArea extends StatelessWidget {
  final ColorScheme cs;
  final String value;
  const _TextArea({required this.cs, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.surfaceContainerHigh)),
    child: Text(value, style: TextStyle(fontSize: 12, color: cs.onSurface, height: 1.5)),
  );
}

class _Pill extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final bool active;
  const _Pill({required this.cs, required this.label, this.active = false});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(color: active ? cs.primary : cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(20), border: active ? null : Border.all(color: cs.surfaceContainerHigh)),
    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w400, color: active ? cs.onPrimary : cs.onSurfaceVariant)),
  );
}

class _THead extends StatelessWidget {
  final ColorScheme cs;
  final String text;
  const _THead({required this.cs, required this.text});

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text(text.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5)));
}

class _CheckRow extends StatelessWidget {
  final ColorScheme cs;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  const _CheckRow({required this.cs, required this.value, required this.onChanged, required this.label});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!value),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 16, height: 16, decoration: BoxDecoration(color: value ? cs.primary : cs.surface, borderRadius: BorderRadius.circular(4), border: Border.all(color: value ? cs.primary : cs.surfaceContainerHigh)), child: value ? Icon(Icons.check_rounded, size: 11, color: cs.onPrimary) : null),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 12, color: cs.onSurface)),
    ]),
  );
}