with open("colors_out.txt", "r") as f:
    lines = f.readlines()
    
seen_pure_white = False
seen_workspace_light = False

new_lines = []
for line in lines:
    if "pureWhite =" in line:
        if seen_pure_white:
            continue
        seen_pure_white = True
    if "workspaceLight =" in line:
        if seen_workspace_light:
            continue
        seen_workspace_light = True
    new_lines.append(line)

with open("colors_out_fixed.txt", "w") as f:
    f.writelines(new_lines)
