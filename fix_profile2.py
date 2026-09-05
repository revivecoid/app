import io
import re

path = 'lib/features/customer_app/profile/presentation/customer_profile_screen.dart'
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace("'Toyota Innova Zenix 2.0 Q Hybrid'", "title")
text = text.replace("'Honda HR-V 1.5 RS Turbo'", "title")
text = text.replace("'B 1984 REV'", "subtitle")
text = text.replace("'B 2401 TJK'", "subtitle")
text = text.replace("const Text(title", "Text(title")
text = text.replace("const Text(subtitle", "Text(subtitle")

text = text.replace("'#JB-03537083'", "'#JB-$jobId'")
text = text.replace("'Toyota Innova Zenix   Panel Respray & Blend'", "title")
text = text.replace("const Text(title", "Text(title")
text = text.replace("'#JB-098122'", "'#JB-$jobId'")
text = text.replace("'Honda HR-V   Glass Coating & Detailing'", "title")
text = text.replace("const Text(title", "Text(title")

def add_title(match):
    return match.group(0) + "\n    final title = '${job['vehicles']?['make'] ?? ''} ${job['vehicles']?['model'] ?? ''}';\n"

text = re.sub(r"final date = job\['created_at'\]\?\.toString\(\)\.substring\(0, 10\) \?\? '';", add_title, text)

text = text.replace("'Body Repair & Paint'", "status")
text = text.replace("const Text(status", "Text(status")
text = text.replace("'Active - In Workshop'", "status")
text = text.replace("'Completed - Delivered'", "status")

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(text)
