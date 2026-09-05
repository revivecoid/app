import io

path = 'lib/features/customer_app/profile/presentation/customer_profile_screen.dart'
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# I will inject `final title = 'Mockup';` at the beginning of each widget builder that has Text(title)
lines = text.split('\n')
new_lines = []
for i, line in enumerate(lines):
    if 'Widget _build' in line and '(BuildContext context' in line:
        new_lines.append(line)
        # Check if the next few lines already define title
        has_title = False
        for j in range(1, 10):
            if i+j < len(lines):
                if 'final title =' in lines[i+j]:
                    has_title = True
                    break
                if 'Widget ' in lines[i+j]:
                    break
        if not has_title:
            new_lines.append("    final title = 'Mockup';")
    else:
        new_lines.append(line)

with io.open(path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(new_lines))
