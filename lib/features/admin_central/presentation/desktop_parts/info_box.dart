part of '../master_admin_desktop.dart';

// ─── Info Box ─────────────────────────────────────────────────────────────────

class _InfoBox extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final String title, subtitle;
  const _InfoBox(
      {required this.cs,
      required this.icon,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Icon(icon, size: 48, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: TextStyle(
                fontSize: 13, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

