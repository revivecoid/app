import io
import re

path = 'lib/features/customer_app/profile/presentation/customer_profile_screen.dart'
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Replace methods using regex to ignore leading whitespace
text = re.sub(r'([ \t]*)Widget _buildVehicleHealthy\(BuildContext context\) \{', r'\1Widget _buildVehicleHealthy(BuildContext context, Map<String, dynamic> v) {\n\1  final title = "${v[\'make\']} ${v[\'model\']}";\n\1  final subtitle = "${v[\'year\']} • ${v[\'license_plate\']}";', text)
text = re.sub(r'([ \t]*)Widget _buildVehicleInRepair\(BuildContext context\) \{', r'\1Widget _buildVehicleInRepair(BuildContext context, Map<String, dynamic> v) {\n\1  final title = "${v[\'make\']} ${v[\'model\']}";\n\1  final subtitle = "${v[\'year\']} • ${v[\'license_plate\']}";', text)
text = re.sub(r'([ \t]*)Widget _buildHistoryActive\(BuildContext context\) \{', r'\1Widget _buildHistoryActive(BuildContext context, Map<String, dynamic> job) {\n\1  final jobId = job[\'id\']?.toString().substring(0, 8) ?? \'\';\n\1  final status = job[\'status\']?.toString() ?? \'Unknown\';\n\1  final date = job[\'created_at\']?.toString().substring(0, 10) ?? \'\';', text)
text = re.sub(r'([ \t]*)Widget _buildHistoryCompleted\(BuildContext context\) \{', r'\1Widget _buildHistoryCompleted(BuildContext context, Map<String, dynamic> job) {\n\1  final jobId = job[\'id\']?.toString().substring(0, 8) ?? \'\';\n\1  final status = job[\'status\']?.toString() ?? \'Completed\';\n\1  final date = job[\'created_at\']?.toString().substring(0, 10) ?? \'\';', text)

text = text.replace("'Honda Civic RS'", "title")
text = text.replace("'2023 • B 1984 REV'", "subtitle")
text = text.replace("'Toyota Zenix Hybrid'", "title")
text = text.replace("'2024 • B 2024 ZEN'", "subtitle")

text = text.replace("'#JB-03537083'", "'#JB-$jobId'")
text = text.replace("'Body Repair & Paint'", "status")
text = text.replace("'Active - In Workshop'", "'Active'")

text = text.replace("'#JB-098122'", "'#JB-$jobId'")
text = text.replace("'Completed - Delivered'", "status")

# Garage section replacement
text = re.sub(
    r'[ \t]*_buildVehicleInRepair\(context\),\s*const SizedBox\(height: 16\),\s*_buildVehicleHealthy\(context\),\s*const SizedBox\(height: 16\),',
    r'''                    ...ref.watch(customerVehiclesProvider).when(
                      data: (vehicles) => vehicles.map((v) => Padding(padding: const EdgeInsets.only(bottom: 16), child: _buildVehicleHealthy(context, v))).toList(),
                      loading: () => [const Center(child: CircularProgressIndicator())],
                      error: (_, __) => [const Text('Failed to load vehicles')],
                    ),''',
    text
)

# History section replacement
text = re.sub(
    r'[ \t]*_buildHistoryActive\(context\),\s*const SizedBox\(height: 12\),\s*_buildHistoryCompleted\(context\),',
    r'''                    ...ref.watch(customerJobsProvider).when(
                      data: (jobs) => jobs.map((job) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _buildHistoryActive(context, job))).toList(),
                      loading: () => [const Center(child: CircularProgressIndicator())],
                      error: (_, __) => [const Text('Failed to load jobs')],
                    ),''',
    text
)

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(text)
