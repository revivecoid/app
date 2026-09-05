import io
import re

path = 'lib/features/customer_app/profile/presentation/customer_profile_screen.dart'
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# I will just replace ALL `Text(title, ...)` with `Text('Mockup', ...)`
text = re.sub(r"Text\(title,\s*style:\s*const TextStyle\(fontSize: 16,\s*fontWeight: FontWeight\.bold,\s*color: AppColors\.sleekBlack\)\)", "const Text('Mockup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.sleekBlack))", text)
text = re.sub(r"Text\(title,\s*style:\s*TextStyle\(fontSize: 16,\s*fontWeight: FontWeight\.bold,\s*color: AppColors\.sleekBlack\)\)", "const Text('Mockup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.sleekBlack))", text)
text = re.sub(r"Text\(title,\s*style:\s*const TextStyle\(fontSize: 12,\s*fontWeight: FontWeight\.bold,\s*color: AppColors\.sleekBlack\)\)", "const Text('Mockup', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.sleekBlack))", text)
text = re.sub(r"Text\(title,\s*style:\s*const TextStyle\(fontSize: 14,\s*fontWeight: FontWeight\.bold,\s*color: AppColors\.sleekBlack\)\)", "const Text('Mockup', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.sleekBlack))", text)

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(text)
