import io
import re

path_router = 'lib/app_router.dart'
with io.open(path_router, 'r', encoding='utf-8') as f:
    text = f.read()

text = re.sub(
    r"path:\s*'/booking/schedule',\s*builder:\s*\(context,\s*state\)\s*=>\s*const\s*BookingSchedulingScreen\(\),",
    r"path: '/booking/schedule/:jobId',\n      builder: (context, state) {\n        final jobId = state.pathParameters['jobId']!;\n        return BookingSchedulingScreen(jobId: jobId);\n      },",
    text
)

with io.open(path_router, 'w', encoding='utf-8') as f:
    f.write(text)
