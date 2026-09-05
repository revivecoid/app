import re
with open("lib/features/customer_app/estimator/presentation/estimator_screen.dart", "r") as f:
    lines = f.readlines()

def remove_const(line_idx):
    # Walk backward to find the const keyword and remove it
    for i in range(line_idx, -1, -1):
        if "const " in lines[i]:
            lines[i] = lines[i].replace("const ", "")
            break

# The lines reported by flutter analyze
error_lines = [359, 395, 585, 850, 896, 906, 932, 1063]

for ln in error_lines:
    remove_const(ln - 1)

with open("lib/features/customer_app/estimator/presentation/estimator_screen.dart", "w") as f:
    f.writelines(lines)
