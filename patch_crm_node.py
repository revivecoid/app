import re

file_path = "lib/features/admin_central/presentation/admin_dashboard_controller.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add fields to PartnerCrmNode
if 'final bool autoAssignActive;' not in content:
    content = re.sub(
        r'(final int\? bayCapacity;\n)',
        r'\1  final bool autoAssignActive;\n  final int autoAssignPriority;\n  final int autoAssignCapacity;\n',
        content,
        count=1
    )
    content = re.sub(
        r'(this\.bayCapacity,\n  \}\);)',
        r'this.bayCapacity,\n    this.autoAssignActive = false,\n    this.autoAssignPriority = 999,\n    this.autoAssignCapacity = 10,\n  });',
        content,
        count=1
    )

# 2. Add to mapping in _fetchCrmData
mapping_search = """        .map((p) => PartnerCrmNode(
              id: p['id'],
              shopName: p['shop_name'] ?? 'Unknown Shop',
              tier: 'T${p['tier'] ?? 3}',
              isActive: p['is_active'] == true,
              serviceArea: p['service_area'],
              bayCapacity: p['working_bays'],"""
if mapping_search in content:
    replacement = """        .map((p) => PartnerCrmNode(
              id: p['id'],
              shopName: p['shop_name'] ?? 'Unknown Shop',
              tier: 'T${p['tier'] ?? 3}',
              isActive: p['is_active'] == true,
              serviceArea: p['service_area'],
              bayCapacity: p['working_bays'],
              autoAssignActive: p['auto_assign_active'] == true,
              autoAssignPriority: p['auto_assign_priority'] ?? 999,
              autoAssignCapacity: p['auto_assign_capacity'] ?? 10,"""
    content = content.replace(mapping_search, replacement)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("Node patched.")
