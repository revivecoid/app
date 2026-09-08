import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';
import '../theme/app_theme.dart';

/// Call [AppSettingsSheet.show] from anywhere to open the language + theme panel.
class AppSettingsSheet {
  static void show(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _SettingsPanelBody(),
    );
  }
}

class _SettingsPanelBody extends ConsumerWidget {
  const _SettingsPanelBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context);
    final currentLocale = ref.watch(localeProvider);
    final currentTheme = ref.watch(themeModeProvider);
    final l = AppL.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(children: [
            Icon(Icons.tune_rounded, size: 22, color: cs.primary),
            const SizedBox(width: 10),
            Text(l.settings,
                style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 28),

          // ── Language ──────────────────────────────────────────────────────
          _SectionLabel(l.language, Icons.language_rounded),
          const SizedBox(height: 10),
          Row(children: [
            _LocaleChip(
              label: '🇮🇩  ${l.languageId}',
              selected: currentLocale.languageCode == 'id',
              onTap: () => ref.read(localeProvider.notifier).setLocale(const Locale('id')),
            ),
            const SizedBox(width: 10),
            _LocaleChip(
              label: '🇬🇧  ${l.languageEn}',
              selected: currentLocale.languageCode == 'en',
              onTap: () => ref.read(localeProvider.notifier).setLocale(const Locale('en')),
            ),
          ]),
          const SizedBox(height: 28),

          // ── Appearance ────────────────────────────────────────────────────
          _SectionLabel(l.appearance, Icons.brightness_6_rounded),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 8, children: [
            _ThemeChip(
              label: l.lightMode,
              icon: Icons.light_mode_outlined,
              selected: currentTheme == ThemeMode.light,
              onTap: () => ref.read(themeModeProvider.notifier).state = ThemeMode.light,
            ),
            _ThemeChip(
              label: l.darkMode,
              icon: Icons.dark_mode_outlined,
              selected: currentTheme == ThemeMode.dark,
              onTap: () => ref.read(themeModeProvider.notifier).state = ThemeMode.dark,
            ),
            _ThemeChip(
              label: l.systemDefault,
              icon: Icons.brightness_auto_outlined,
              selected: currentTheme == ThemeMode.system,
              onTap: () => ref.read(themeModeProvider.notifier).state = ThemeMode.system,
            ),
          ]),
          const SizedBox(height: 32),

          // Done button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
              ),
              onPressed: () => Navigator.pop(context),
              child: Text(l.done),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 14, color: cs.onSurfaceVariant),
      const SizedBox(width: 6),
      Text(label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
    ]);
  }
}

class _LocaleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LocaleChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeChip({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16,
              color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }
}
