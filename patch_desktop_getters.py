import re

file_path = "lib/features/admin_central/presentation/master_admin_desktop.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

content = content.replace("final bool aaActive = p.raw['auto_assign_active'] == true;", "final bool aaActive = p.autoAssignActive;")
content = content.replace("final int priority = p.raw['auto_assign_priority'] ?? 999;", "final int priority = p.autoAssignPriority;")
content = content.replace("final int capacity = p.raw['auto_assign_capacity'] ?? 10;", "final int capacity = p.autoAssignCapacity;")
content = content.replace("final int activeJobs = p.activeJobsCount;", "final int activeJobs = p.activeVolume;")
content = content.replace("p.status.toUpperCase()", "(p.isActive ? 'ACTIVE' : 'INACTIVE')")
content = content.replace("p.status == 'active'", "p.isActive")
content = content.replace("Text(p.serviceArea,", "Text(p.serviceArea ?? 'Unknown',")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("Desktop getters patched.")
