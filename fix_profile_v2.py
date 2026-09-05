import io
import re

path = 'lib/features/customer_app/profile/presentation/customer_profile_screen.dart'
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Replace StreamProvider with FutureProvider for vehicles
old_vehicles_provider = """final customerVehiclesProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return const Stream.empty();
  return Supabase.instance.client
      .from('vehicles')
      .stream(primaryKey: ['id'])
      .eq('customer_id', user.id);
});"""

new_vehicles_provider = """final customerVehiclesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];
  final data = await Supabase.instance.client
      .from('vehicles')
      .select()
      .eq('customer_id', user.id);
  return List<Map<String, dynamic>>.from(data);
});"""

text = text.replace(old_vehicles_provider, new_vehicles_provider)

# Replace StreamProvider with FutureProvider for jobs
old_jobs_provider = """final customerJobsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return const Stream.empty();
  return Supabase.instance.client
      .from('repair_jobs')
      .stream(primaryKey: ['id'])
      .eq('customer_id', user.id)
      .neq('status', '8_completed')
      .neq('status', '9_cancelled');
});"""

new_jobs_provider = """final customerJobsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];
  final data = await Supabase.instance.client
      .from('repair_jobs')
      .select('*, vehicles(*)')
      .eq('customer_id', user.id)
      .neq('status', '8_completed')
      .neq('status', '9_cancelled');
  return List<Map<String, dynamic>>.from(data);
});"""

text = text.replace(old_jobs_provider, new_jobs_provider)

# Fix _buildHistoryActive hardcoded strings
text = re.sub(r"const Text\('Toyota Innova Zenix [^']*', style: TextStyle\(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.sleekBlack\)\)", "Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.sleekBlack))", text)
text = re.sub(r"const Text\('Toyota Innova Zenix 2\.0 Q Hybrid', style: TextStyle\(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.sleekBlack\)\)", "Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.sleekBlack))", text)

# Fix _buildHistoryCompleted hardcoded strings
text = re.sub(r"const Text\('Honda HR-V [^']*', style: TextStyle\(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.sleekBlack\)\)", "Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.sleekBlack))", text)

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(text)
