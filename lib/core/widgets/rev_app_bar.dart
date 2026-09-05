import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class ReVAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final bool centerTitle;
  final Color? backgroundColor;
  final bool showBackButton;

  const ReVAppBar({
    super.key,
    this.title,
    this.actions,
    this.centerTitle = false,
    this.backgroundColor,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final theme = Theme.of(context);
    
    final themeToggleBtn = IconButton(
      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: theme.colorScheme.onSurfaceVariant),
      tooltip: 'Toggle Theme',
      onPressed: () {
        ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark;
      },
    );

    final finalActions = <Widget>[];
    if (actions != null) {
      finalActions.addAll(actions!);
    }
    finalActions.add(themeToggleBtn);
    
    // Add User Profile Avatar with popup menu
    final user = Supabase.instance.client.auth.currentUser;
    final userName = user?.userMetadata?['full_name']?.toString() ??
        user?.userMetadata?['name']?.toString() ?? '';
    final userEmail = user?.email ?? '';
    final avatarUrl = user?.userMetadata?['avatar_url']?.toString();
    String initials = '?';
    if (userName.trim().isNotEmpty) {
      final parts = userName.trim().split(' ');
      initials = parts.length >= 2
          ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
          : parts[0][0].toUpperCase();
    } else if (userEmail.isNotEmpty) {
      initials = userEmail[0].toUpperCase();
    }

    finalActions.add(
      PopupMenuButton<String>(
        offset: const Offset(0, 48),
        tooltip: 'Account',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (value) async {
          switch (value) {
            case 'profile':
              context.push('/profile');
              break;
            case 'settings':
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Settings coming soon'),
                    behavior: SnackBarBehavior.floating),
              );
              break;
            case 'logout':
              await Supabase.instance.client.auth.signOut();
              break;
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            enabled: false,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName.isNotEmpty ? userName : 'Revive Member',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(userEmail,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.daysGray)),
                const Divider(height: 16),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'profile',
            child: Row(children: [
              const Icon(Icons.person_outline,
                  size: 18, color: AppColors.daysGray),
              const SizedBox(width: 10),
              const Text('My Profile'),
            ]),
          ),
          PopupMenuItem(
            value: 'settings',
            child: Row(children: [
              const Icon(Icons.settings_outlined,
                  size: 18, color: AppColors.daysGray),
              const SizedBox(width: 10),
              const Text('Settings'),
            ]),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'logout',
            child: Row(children: [
              Icon(Icons.logout, size: 18, color: AppColors.primaryContainer),
              const SizedBox(width: 10),
              Text('Log Out',
                  style: TextStyle(
                      color: AppColors.primaryContainer,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
        ],
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          clipBehavior: Clip.antiAlias,
          child: avatarUrl != null && avatarUrl.isNotEmpty
              ? Image.network(avatarUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ))
              : Center(
                  child: Text(initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12))),
        ),
      ),
    );


    final defaultLogoArea = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/revive_logo.png',
          height: 28,
          fit: BoxFit.contain,
          color: isDark ? Colors.white : AppColors.fireRed,
        ),
        const SizedBox(width: 8),
        Text(
          're-V',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.sleekBlack,
          ),
        ),
      ],
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: (backgroundColor ?? theme.colorScheme.surface).withValues(alpha: 0.8),
          child: SafeArea(
            bottom: false,
            child: Container(
              height: kToolbarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    offset: const Offset(0, 1),
                    blurRadius: 8,
                  )
                ],
              ),
              child: Row(
                children: [
                  if (showBackButton)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      color: theme.colorScheme.onSurface,
                      onPressed: () => context.pop(),
                    ),
                  InkWell(
                    onTap: () {
                      if (GoRouterState.of(context).uri.path != '/') {
                        context.go('/');
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: defaultLogoArea,
                  ),
                  if (title != null) ...[
                    const SizedBox(width: 16),
                    Expanded(child: Align(alignment: centerTitle ? Alignment.center : Alignment.centerLeft, child: title!)),
                  ] else
                    const Spacer(),
                  ...finalActions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}