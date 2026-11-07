/// Spare-parts estimation widget for the estimator result screen.
///
/// Shows the AI-suggested spare parts list per damaged panel.
/// Prices are NOT yet available — the [SparePartItem.price] field is null
/// until the vendor database integration is connected.
library;

import 'package:flutter/material.dart';
import '../../../../../../../../core/theme/app_theme.dart';

// ── Data model ───────────────────────────────────────────────────────────────

/// A single spare part that may be needed for a panel repair.
class SparePartItem {
  final String name;
  final String? partNumber;   // null until vendor DB connected
  final double? price;        // null = "Harga belum tersedia"
  final int quantity;
  final String reason;        // e.g. "requires_replacement" / "dent repair"

  const SparePartItem({
    required this.name,
    this.partNumber,
    this.price,
    this.quantity = 1,
    required this.reason,
  });

  factory SparePartItem.fromJson(Map<String, dynamic> json) {
    return SparePartItem(
      name: (json['name'] as String? ?? '').trim(),
      partNumber: json['part_number'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      reason: (json['reason'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (partNumber != null) 'part_number': partNumber,
    if (price != null) 'price': price,
    'quantity': quantity,
    'reason': reason,
  };
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Parse spare_parts_needed from a raw panel map returned by vision-estimation.
List<SparePartItem> parseSpareParts(Map<String, dynamic> panel) {
  final raw = panel['spare_parts_needed'];
  if (raw == null) return _inferSpareParts(panel);
  if (raw is List) {
    return raw
        .whereType<Map<String, dynamic>>()
        .map(SparePartItem.fromJson)
        .where((p) => p.name.isNotEmpty)
        .toList();
  }
  return _inferSpareParts(panel);
}

/// Parse all spare parts needing replacement from the assessment object,
/// checking both the dedicated `pergantian_sparepart` list and per-panel lists.
List<SparePartItem> parsePergantianSparepart(Map<String, dynamic>? structuredData) {
  if (structuredData == null) return [];
  final assessment = structuredData['assessment'];
  if (assessment is! Map<String, dynamic>) return [];

  final List<SparePartItem> items = [];
  final Set<String> seenNames = {};

  // 1. Direct pergantian_sparepart array from AI loss adjuster
  final rawList = assessment['pergantian_sparepart'] ?? structuredData['pergantian_sparepart'];
  if (rawList is List && rawList.isNotEmpty) {
    for (final raw in rawList) {
      if (raw is Map<String, dynamic>) {
        final name = (raw['name'] as String? ?? '').trim();
        if (name.isNotEmpty && seenNames.add(name.toLowerCase())) {
          items.add(SparePartItem(
            name: name,
            quantity: (raw['quantity'] as num?)?.toInt() ?? 1,
            reason: (raw['condition'] as String? ?? raw['reason'] as String? ?? 'Perlu diganti').trim(),
          ));
        }
      }
    }
  }

  // 2. Aggregate from damaged_panels_detail spare_parts_needed
  final panels = assessment['damaged_panels_detail'];
  if (panels is List) {
    for (final p in panels) {
      if (p is Map<String, dynamic>) {
        for (final item in parseSpareParts(p)) {
          if (seenNames.add(item.name.toLowerCase())) {
            items.add(item);
          }
        }
      }
    }
  }

  return items;
}

/// Fallback: infer likely spare parts from damage flags when AI did not return
/// a spare_parts_needed list (older AI response format or parse fallback).
List<SparePartItem> _inferSpareParts(Map<String, dynamic> panel) {
  final parts = <SparePartItem>[];
  final panelName = (panel['panel_name'] as String? ?? '').trim();
  final requiresReplacement = panel['requires_replacement'] == true ||
      (panel['broken_found'] as num? ?? 0) > 0;

  if (requiresReplacement && panelName.isNotEmpty) {
    parts.add(SparePartItem(
      name: 'Panel $panelName (pengganti)',
      reason: 'Pecah / ringsek — perlu diganti',
    ));
  }

  return parts;
}

// ── Widget ───────────────────────────────────────────────────────────────────

/// Collapsible spare-parts list card for a single damaged panel.
///
/// Shows part name, quantity, reason, and a "Harga belum tersedia" badge
/// when [SparePartItem.price] is null. Renders nothing if [parts] is empty.
class SparePartsPanel extends StatefulWidget {
  final List<SparePartItem> parts;
  final bool isDark;

  const SparePartsPanel({
    super.key,
    required this.parts,
    required this.isDark,
  });

  @override
  State<SparePartsPanel> createState() => _SparePartsPanelState();
}

class _SparePartsPanelState extends State<SparePartsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.parts.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final isDark = widget.isDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        // ── Toggle row ────────────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.build_outlined,
                  size: 14,
                  color: isDark ? AppColors.onSurfaceVariant : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Spare Parts Estimasi (${widget.parts.length})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.onSurfaceVariant : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'HARGA BELUM TERSEDIA',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: isDark ? AppColors.onSurfaceVariant : cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),

        // ── Expandable list ───────────────────────────────────────────
        if (_expanded) ...[
          const SizedBox(height: 6),
          ...widget.parts.map((part) => _SparePartRow(
                part: part,
                isDark: isDark,
              )),
          const SizedBox(height: 4),
          _VendorConnectionNote(isDark: isDark),
        ],
      ],
    );
  }
}

class _SparePartRow extends StatelessWidget {
  final SparePartItem part;
  final bool isDark;

  const _SparePartRow({required this.part, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceContainerLowest
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? AppColors.surfaceContainerHigh : cs.outlineVariant,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quantity badge
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.fireRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${part.quantity}x',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: AppColors.fireRed,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Name + reason
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  part.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.onSurface : cs.onSurface,
                  ),
                ),
                if (part.partNumber != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'P/N: ${part.partNumber}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? AppColors.onSurfaceVariant : cs.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  part.reason,
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: isDark ? AppColors.onSurfaceVariant : cs.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Price
          _PriceChip(price: part.price),
        ],
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  final double? price;
  const _PriceChip({required this.price});

  @override
  Widget build(BuildContext context) {
    if (price != null) {
      return Text(
        'Rp ${_fmt(price!)}',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppColors.fireRed,
        ),
      );
    }
    // Do not show raw TBD or price placeholder as requested
    return const SizedBox.shrink();
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _VendorConnectionNote extends StatelessWidget {
  final bool isDark;
  const _VendorConnectionNote({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: Colors.blue[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ketersediaan dan harga sparepart masih membutuhkan konfirmasi dari vendor / bengkel mitra.',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: isDark ? AppColors.onSurface : cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standalone Card displaying Table 2: Pergantian Sparepart
/// (matching loss assessment format, without showing raw price placeholders).
class PergantianSparepartCard extends StatelessWidget {
  final List<SparePartItem> parts;
  final bool isDark;

  const PergantianSparepartCard({
    super.key,
    required this.parts,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceContainerLowest : cs.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cs.onSurface.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceContainerLow : cs.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.blue[700],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.build_circle_outlined, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pergantian Sparepart',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.onSurface : cs.onSurface,
                          ),
                        ),
                        Text(
                          'Komponen rusak teridentifikasi yang perlu diganti',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.onSurfaceVariant : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceContainer : cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${parts.length} Part',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content body
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info notice
                _VendorConnectionNote(isDark: isDark),
                const SizedBox(height: 10),

                // List of broken/replacement parts
                ...parts.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final part = entry.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceContainerLow : cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${idx + 1}.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.onSurfaceVariant : cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${part.quantity}x',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            part.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.onSurface : cs.onSurface,
                            ),
                          ),
                        ),
                        if (part.reason.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              part.reason,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[700],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
