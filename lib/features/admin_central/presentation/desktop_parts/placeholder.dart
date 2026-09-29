part of '../master_admin_desktop.dart';

// ─── Placeholder ──────────────────────────────────────────────────────────────

class _PlaceholderContent extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final String? subtitle;
  final IconData? icon;
  const _PlaceholderContent({
    required this.cs,
    required this.label,
    this.subtitle,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
        Icon(icon ?? Icons.construction_rounded,
            size: 48, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(label,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        const SizedBox(height: 8),
        Text(subtitle ?? 'This section is under construction.',
            style: TextStyle(
                fontSize: 14, color: cs.onSurfaceVariant)),
      ])),
    );
  }
}

