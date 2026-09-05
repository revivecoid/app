import io
path = 'lib/features/customer_app/tracking/presentation/live_stepper_timeline.dart'
content = io.open(path, 'r', encoding='utf-8').read()
content = content.replace("const Text(\n                        (job['status']", "Text(\n                        (job['status']")
io.open(path, 'w', encoding='utf-8').write(content)
