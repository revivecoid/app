import io
import re

path = 'lib/features/customer_app/profile/presentation/customer_profile_screen.dart'
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Fix signatures and variable usage
text = text.replace(
    "Widget _buildVehicleInRepair(BuildContext context) {",
    "Widget _buildVehicleInRepair(BuildContext context, Map<String, dynamic> v) {\n    final title = '${v['make'] ?? ''} ${v['model'] ?? ''}';\n    final subtitle = '${v['year'] ?? ''} • ${v['license_plate'] ?? ''}';"
)
text = text.replace(
    "Widget _buildVehicleHealthy(BuildContext context) {",
    "Widget _buildVehicleHealthy(BuildContext context, Map<String, dynamic> v) {\n    final title = '${v['make'] ?? ''} ${v['model'] ?? ''}';\n    final subtitle = '${v['year'] ?? ''} • ${v['license_plate'] ?? ''}';"
)
text = text.replace(
    "Widget _buildHistoryActive(BuildContext context) {",
    "Widget _buildHistoryActive(BuildContext context, Map<String, dynamic> job) {\n    final jobId = job['id']?.toString().substring(0, 8) ?? '';\n    final status = job['status']?.toString() ?? 'Unknown';\n    final title = '${job['vehicles']?['make'] ?? ''} ${job['vehicles']?['model'] ?? ''}';\n    final date = job['created_at']?.toString().substring(0, 10) ?? '';"
)
text = text.replace(
    "Widget _buildHistoryCompleted(BuildContext context) {",
    "Widget _buildHistoryCompleted(BuildContext context, Map<String, dynamic> job) {\n    final jobId = job['id']?.toString().substring(0, 8) ?? '';\n    final status = job['status']?.toString() ?? 'Unknown';\n    final title = '${job['vehicles']?['make'] ?? ''} ${job['vehicles']?['model'] ?? ''}';\n    final date = job['created_at']?.toString().substring(0, 10) ?? '';"
)

# Remove `const` from Text widgets that use variables
text = text.replace("const Text(title", "Text(title")
text = text.replace("const Text(subtitle", "Text(subtitle")
text = text.replace("const Text(status", "Text(status")
text = text.replace("const Text('#JB-$jobId'", "Text('#JB-$jobId'")

# We also need to remove the previous botched "final title = '${job.containsKey...'" that fix_profile2.py inserted!
text = re.sub(r"    final title = '\$\{job\['vehicles'\]\?\['make'\] \?\? ''\} \$\{job\['vehicles'\]\?\['model'\] \?\? ''\}';\n", "", text)


with io.open(path, 'w', encoding='utf-8') as f:
    f.write(text)
