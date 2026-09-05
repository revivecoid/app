import io

path = 'lib/features/customer_app/tracking/presentation/live_stepper_timeline.dart'
content = io.open(path, 'r', encoding='utf-8').read()

old_build = '''  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final cardColor = isDark ? AppColors.surfaceContainerLowest : Colors.white;
    final iconBgColor = isDark ? AppColors.surfaceContainerLow : Colors.grey.withValues(alpha: 0.1);
    final textMutedColor = isDark ? AppColors.onSurfaceVariant : Colors.grey[600]!;

    return Scaffold('''

new_build = '''  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final cardColor = isDark ? AppColors.surfaceContainerLowest : Colors.white;
    final iconBgColor = isDark ? AppColors.surfaceContainerLow : Colors.grey.withValues(alpha: 0.1);
    final textMutedColor = isDark ? AppColors.onSurfaceVariant : Colors.grey[600]!;

    final jobAsync = ref.watch(jobTrackerProvider(jobId));

    return Scaffold('''

content = content.replace(old_build, new_build)

old_body = '''      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Chip & Quick Actions Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container('''

new_body = '''      body: jobAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (job) => SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Chip & Quick Actions Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container('''

content = content.replace(old_body, new_body)

content = content.replace("'STAGE 5 OF 7 ACTIVE'", "(job['status'] as String? ?? 'UNKNOWN').toUpperCase()")
content = content.replace("Text('ETA: 14 Oct, 16:30'", "Text('Updated: ' + job['created_at'].toString().substring(0, 10)")
content = content.replace("        ), // End SingleChildScrollView\n      ), // End body", "        ), // End SingleChildScrollView\n      ), // End body")
# Actually, the original file has:
#       ),
#     );
#   }
# }
content = content.replace("        ), // End SingleChildScrollView\n      ), // End body", "")

io.open(path, 'w', encoding='utf-8').write(content)
