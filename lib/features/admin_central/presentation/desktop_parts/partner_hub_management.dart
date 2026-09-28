part of '../master_admin_desktop.dart';

// ─── Partner & Hub Management ─────────────────────────────────────────────────

class _PartnerHubContent extends StatelessWidget {
  final ColorScheme cs;
  final AdminDashboardState state;
  final AdminDashboardController controller;
  const _PartnerHubContent(
      {required this.cs,
      required this.state,
      required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      _Chip(
          cs: cs,
          label: 'Partner & Hub Management',
          bgColor: cs.surfaceContainerHigh,
          fgColor: cs.primary),
      const SizedBox(height: 6),
      Text('Partner Network CRM',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: cs.onSurface)),
      const SizedBox(height: 20),

      // Sub-tabs
      DefaultTabController(
        length: 2,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          TabBar(
            isScrollable: true,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            tabs: const [
              Tab(text: 'Active Partner Workshops'),
              Tab(text: 'Commlink & Messages'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 600,
            child: TabBarView(children: [
              // Tab 1: Active Partners
              Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                ...state.partners.isEmpty
                    ? [
                        _InfoBox(
                            cs: cs,
                            icon: Icons.warehouse_outlined,
                            title: 'No Active Partners',
                            subtitle:
                                'Register workshops in Workshop Settings.')
                      ]
                    : state.partners.map((p) => Container(
                          margin:
                              const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                              color: cs.surfaceContainerLowest,
                              borderRadius:
                                  BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                    color: cs.onSurface
                                        .withValues(alpha: 0.04),
                                    blurRadius: 4)
                              ]),
                          child: ListTile(
                            onTap: () => context.push(
                                '/admin-central/partner/${p.id}'),
                            leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                    color: p.isActive
                                        ? cs.primaryContainer
                                            .withValues(alpha: 0.3)
                                        : cs.surfaceContainerHigh,
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                child: Icon(Icons.warehouse,
                                    color: p.isActive
                                        ? cs.primary
                                        : cs.onSurfaceVariant)),
                            title: Text(p.shopName,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface)),
                            subtitle: Text(
                                '${p.tier.toUpperCase()} · ${p.activeVolume} active · ${p.avgVelocityDays}d avg',
                                style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        cs.onSurfaceVariant)),
                            trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              if (p.unreadMessageCount > 0)
                                Container(
                                    margin: const EdgeInsets
                                        .only(right: 8),
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2),
                                    decoration: BoxDecoration(
                                        color: cs.primary,
                                        borderRadius:
                                            BorderRadius.circular(
                                                10)),
                                    child: Text(
                                        '${p.unreadMessageCount}',
                                        style: TextStyle(
                                            color: cs.onPrimary,
                                            fontSize: 11,
                                            fontWeight:
                                                FontWeight.w700))),
                              Switch(
                                  value: p.isActive,
                                  activeThumbColor: cs.primary,
                                  onChanged: (v) => controller
                                      .togglePartnerStatus(
                                          p.id, v)),
                            ]),
                          ),
                        )),
              ]),
              // Tab 2: Commlink
              _InfoBox(
                  cs: cs,
                  icon: Icons.forum_outlined,
                  title: 'Partner Commlink',
                  subtitle:
                      'Open a partner profile to access the direct message channel.'),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

