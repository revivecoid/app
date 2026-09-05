import io

path = 'lib/features/customer_app/profile/presentation/customer_profile_screen.dart'
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# _buildVehicleHealthy
text = text.replace("const Text('Honda HR-V 1.5 RS Turbo', style:", "Text(title, style:")
text = text.replace("const Text('B 2401 TJK', style:", "Text(subtitle, style:")

# _buildHistoryActive
text = text.replace("const Text('#JB-03537083', style:", "Text('#JB-$jobId', style:")
text = text.replace("const Text('Toyota Innova Zenix   Panel Respray & Blend', style:", "Text(title, style:")
text = text.replace("const Text('Active - In Workshop', style:", "Text(status, style:")
text = text.replace("const Text('14 Aug 2026', style:", "Text(date, style:")

# _buildHistoryCompleted
text = text.replace("const Text('#JB-098122', style:", "Text('#JB-$jobId', style:")
text = text.replace("const Text('Honda HR-V   Glass Coating & Detailing', style:", "Text(title, style:")
text = text.replace("const Text('Completed - Delivered', style:", "Text(status, style:")
text = text.replace("const Text('28 Jul 2026', style:", "Text(date, style:")

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(text)
