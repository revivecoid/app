import io
import re

path = 'lib/features/customer_app/tracking/presentation/live_stepper_timeline.dart'
content = io.open(path, 'r', encoding='utf-8').read()

content = re.sub(
    r'(final textMutedColor = .*?;)',
    r'\1\n\n    final jobAsync = ref.watch(jobTrackerProvider(jobId));',
    content
)
content = content.replace("'STAGE 5 OF 7 ACTIVE'", "(job['status'] as String? ?? 'UNKNOWN').toUpperCase()")
content = content.replace("Text('ETA: 14 Oct, 16:30'", "Text('Updated: ' + (job['created_at']?.toString().substring(0, 10) ?? '')")

io.open(path, 'w', encoding='utf-8').write(content)
