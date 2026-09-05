import re, io

path = r'lib\features\customer_app\estimator\presentation\estimator_screen.dart'
with io.open(path, encoding='utf-8') as f:
    lines = f.readlines()

# Find ALL lines containing isDark
isdark_lines = set()
for i, line in enumerate(lines, 1):
    if 'isDark' in line:
        isdark_lines.add(i)

# Now find lines with 'const ' that open a block (no closing on same line)
# and check if any of their nested lines contain isDark
# Simple heuristic: for each 'const' line, check the next 20 lines for isDark
results = []
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    # line itself has const but NOT isDark
    if re.search(r'\bconst\b', stripped) and 'isDark' not in stripped:
        # peek ahead up to 20 lines
        for j in range(i, min(i+20, len(lines)+1)):
            if j in isdark_lines:
                peek = lines[j-1].strip()
                results.append((i, j, stripped[:100], peek[:100]))
                break

for const_ln, dark_ln, const_text, dark_text in results:
    print("CONST at line %d -> isDark at line %d" % (const_ln, dark_ln))
    print("  const: %s" % const_text)
    print("  dark:  %s" % dark_text)
    print()

print("Total: %d suspect const blocks" % len(results))
