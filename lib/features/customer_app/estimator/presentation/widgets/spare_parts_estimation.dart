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

/// Fallback: infer likely spare parts from damage flags when AI did not return
/// a spare_parts_needed list (older AI response format or parse fallback).
List<SparePartItem> _inferSpareParts(Map<String, dynamic> panel) {
  final parts = <SparePartItem>[];
  final panelName = (panel['panel_name'] as String? ?? '').trim();
  final requiresReplacement = panel['requires_replacement'] == true ||
      (panel['broken_found'] as num? ?? 0) > 0;
  final hasDent = (panel['dents_found'] as num? ?? 0) > 0;
  final hasScratch = (panel['scratches_found'] as num? ?? 0) > 0;

  if (requiresReplacement && panelName.isNotEmpty) {
    parts.add(SparePartItem(
      name: 'Panel $panelName (pengganti)',
      reason: 'Panel pecah/ringsek — perlu diganti',
    ));
    parts.add(const SparePartItem(
      name: 'Dempul epoxy primer',
      reason: 'Dasar cat setelah penggantian panel',
    ));
    parts.add(const SparePartItem(
      name: 'Cat warna (basecoat)',
      reason: 'Finishing setelah penggantian panel',
    ));
    parts.add(const SparePartItem(
      name: 'Clear coat',
      reason: 'Lapisan pelindung akhir',
    ));
  } else if (hasDent) {
    parts.add(const SparePartItem(
      name: 'Dempul polyester',
      reason: 'Perbaikan penyok — pengisian permukaan',
    ));
    parts.add(const SparePartItem(
      name: 'Cat warna (basecoat)',
      reason: 'Finishing setelah perbaikan penyok',
    ));
    parts.add(const SparePartItem(
      name: 'Clear coat',
      reason: 'Lapisan pelindung akhir',
    ));
  } else if (hasScratch) {
    parts.add(const SparePartItem(
      name: 'Cat warna (basecoat)',
      reason: 'Perbaikan goresan',
    ));
    parts.add(const SparePartItem(
      name: 'Clear coat',
      reason: 'Lapisan pelindung akhir',
    ));
    parts.add(const SparePartItem(
      name: 'Amplas compound',
      reason: 'Halus permukaan goresan sebelum cat',
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: const Text(
        'TBD',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.orange,
        ),
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.link, size: 12, color: Colors.blue[600]),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Harga spare parts akan ditampilkan setelah integrasi database vendor aktif. Estimasi ini hanya daftar kebutuhan berdasarkan analisis kerusakan.',
              style: TextStyle(
                fontSize: 10,
                height: 1.35,
                color: isDark ? AppColors.onSurfaceVariant : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
