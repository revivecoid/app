import os
file_path = "lib/features/admin_central/presentation/master_admin_desktop.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Update the descriptions to match the new logic exactly
content = content.replace("Fills highest priority workshops to capacity before assigning to lower tiers.", "Fills highest priority to capacity, then lets it drain completely to 0 before assigning to it again.")
content = content.replace("Always tries to assign to the highest priority workshop with available capacity.", "Always assigns to the highest priority workshop that has ANY open slot.")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("Labels updated.")
