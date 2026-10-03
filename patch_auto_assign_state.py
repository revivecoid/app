import re

file_path = "lib/features/admin_central/presentation/admin_dashboard_controller.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add to AdminDashboardState
if 'final Map<String, dynamic>? autoAssignSettings;' not in content:
    content = re.sub(
        r'(final DateTime\? assignDateTo;\n)',
        r'\1\n  final Map<String, dynamic>? autoAssignSettings;\n',
        content,
        count=1
    )
    content = re.sub(
        r'(this\.assignDateTo,\n  \}\);)',
        r'this.assignDateTo,\n    this.autoAssignSettings,\n  });',
        content,
        count=1
    )
    content = re.sub(
        r'(DateTime\? assignDateTo,\n  \}\) \{)',
        r'DateTime? assignDateTo,\n    Map<String, dynamic>? autoAssignSettings,\n  }) {',
        content,
        count=1
    )
    content = re.sub(
        r'(assignDateTo: assignDateTo \?\? this\.assignDateTo,\n    \);)',
        r'assignDateTo: assignDateTo ?? this.assignDateTo,\n      autoAssignSettings: autoAssignSettings ?? this.autoAssignSettings,\n    );',
        content,
        count=1
    )

# 2. Add fetch method
if '_fetchAutoAssignSettings' not in content:
    fetch_method = """
  // ── Auto Assign Settings ──────────────────────────────────────────────────
  Future<void> _fetchAutoAssignSettings() async {
    try {
      final res = await _supabase.from('auto_assign_settings').select().eq('id', 1).maybeSingle();
      if (res != null && mounted) {
        state = state.copyWith(autoAssignSettings: res);
      }
    } catch (e) {
      debugPrint('Error fetching auto assign settings: $e');
    }
  }

  Future<void> updateAutoAssignSettings(Map<String, dynamic> updates) async {
    try {
      await _supabase.from('auto_assign_settings').update(updates).eq('id', 1);
      await _fetchAutoAssignSettings();
      state = state.copyWith(successMessage: 'Auto-assign settings updated');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update auto-assign settings: $e');
    }
  }
  
  Future<void> updatePartnerAutoAssignSettings(String partnerId, Map<String, dynamic> updates) async {
    try {
      await _supabase.from('partners').update(updates).eq('id', partnerId);
      await _fetchCrmData(); // Refresh partners
      state = state.copyWith(successMessage: 'Partner quota updated');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update partner quota: $e');
    }
  }
"""
    content = content.replace("// ── Admin profile ─────────────────────────────────────────────────────────", fetch_method + "\n  // ── Admin profile ─────────────────────────────────────────────────────────")

# 3. Add to init
if '_fetchAutoAssignSettings()' not in content:
    content = content.replace("_fetchDailySettlement(),", "_fetchDailySettlement(),\n        _fetchAutoAssignSettings(),")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("State patched.")
