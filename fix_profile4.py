import io

path = 'lib/features/customer_app/profile/presentation/customer_profile_screen.dart'
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Fix signatures manually
text = text.replace(
    "  Widget _buildVehicleInRepair(BuildContext context) {\n    return Container(",
    "  Widget _buildVehicleInRepair(BuildContext context, Map<String, dynamic> v) {\n    final title = '${v['make'] ?? ''} ${v['model'] ?? ''}';\n    final subtitle = '${v['year'] ?? ''} • ${v['license_plate'] ?? ''}';\n    return Container("
)

text = text.replace(
    "  Widget _buildVehicleHealthy(BuildContext context) {\n    return Container(",
    "  Widget _buildVehicleHealthy(BuildContext context, Map<String, dynamic> v) {\n    final title = '${v['make'] ?? ''} ${v['model'] ?? ''}';\n    final subtitle = '${v['year'] ?? ''} • ${v['license_plate'] ?? ''}';\n    return Container("
)

text = text.replace(
    "  Widget _buildHistoryActive(BuildContext context) {\n    return Container(",
    "  Widget _buildHistoryActive(BuildContext context, Map<String, dynamic> job) {\n    final jobId = job['id']?.toString().substring(0, 8) ?? '';\n    final status = job['status']?.toString() ?? 'Unknown';\n    final title = '${job['vehicles'] != null ? job['vehicles']['make'] ?? '' : ''} ${job['vehicles'] != null ? job['vehicles']['model'] ?? '' : ''}';\n    final date = job['created_at']?.toString().substring(0, 10) ?? '';\n    return Container("
)

text = text.replace(
    "  Widget _buildHistoryCompleted(BuildContext context) {\n    return Container(",
    "  Widget _buildHistoryCompleted(BuildContext context, Map<String, dynamic> job) {\n    final jobId = job['id']?.toString().substring(0, 8) ?? '';\n    final status = job['status']?.toString() ?? 'Unknown';\n    final title = '${job['vehicles'] != null ? job['vehicles']['make'] ?? '' : ''} ${job['vehicles'] != null ? job['vehicles']['model'] ?? '' : ''}';\n    final date = job['created_at']?.toString().substring(0, 10) ?? '';\n    return Container("
)

# And fix the botched previous replacement
text = text.replace("    final title = '${job['vehicles']?['make'] ?? ''} ${job['vehicles']?['model'] ?? ''}';\n", "")
text = text.replace("    final title = '${job.containsKey('vehicles') && job['vehicles'] != null ? job['vehicles']['make'] : ''} ${job.containsKey('vehicles') && job['vehicles'] != null ? job['vehicles']['model'] : ''}';\n", "")
text = text.replace("Text('#JB-$jobId'", "Text('#JB-$jobId'")  # Just in case

# Fix the invalid constant for jobId
text = text.replace("const Text('#JB-$jobId'", "Text('#JB-$jobId'")

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(text)
