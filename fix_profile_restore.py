import io
import re

path = 'lib/features/customer_app/profile/presentation/customer_profile_screen.dart'
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Restore title in _buildVehicleHealthy
text = text.replace(
    "const Text('Mockup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.sleekBlack))",
    "Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.sleekBlack))",
    1
)

# Wait, this is getting messy. Let's just run dart fix, or do it explicitly.
