
import os, io

for r, d, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            filepath = os.path.join(r, f)
            with io.open(filepath, 'r', encoding='utf-8') as file:
                content = file.read()
            if '.withOpacity(' in content:
                content = content.replace('.withOpacity(', '.withValues(alpha: ')
                with io.open(filepath, 'w', encoding='utf-8') as file:
                    file.write(content)

