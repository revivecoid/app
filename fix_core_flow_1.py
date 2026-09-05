import io
import re

# 1. Update app_router.dart
path_router = 'lib/app_router.dart'
with io.open(path_router, 'r', encoding='utf-8') as f:
    text_router = f.read()

text_router = text_router.replace(
    """        GoRoute(
          path: '/booking/schedule',
          builder: (context, state) => const BookingSchedulingScreen(),
        ),""",
    """        GoRoute(
          path: '/booking/schedule/:jobId',
          builder: (context, state) {
            final jobId = state.pathParameters['jobId']!;
            return BookingSchedulingScreen(jobId: jobId);
          },
        ),"""
)

with io.open(path_router, 'w', encoding='utf-8') as f:
    f.write(text_router)

# 2. Update estimator_screen.dart
path_estimator = 'lib/features/customer_app/estimator/presentation/estimator_screen.dart'
with io.open(path_estimator, 'r', encoding='utf-8') as f:
    text_estimator = f.read()

text_estimator = text_estimator.replace(
    "context.push('/checkout/${jobRes['id']}?partnerId=auto_assign');",
    "context.push('/booking/schedule/${jobRes['id']}');"
)

with io.open(path_estimator, 'w', encoding='utf-8') as f:
    f.write(text_estimator)

# 3. Update booking_scheduling_screen.dart
path_booking = 'lib/features/customer_app/order/presentation/booking_scheduling_screen.dart'
with io.open(path_booking, 'r', encoding='utf-8') as f:
    text_booking = f.read()

text_booking = text_booking.replace(
    "const BookingSchedulingScreen({super.key});",
    "final String jobId;\n\n  const BookingSchedulingScreen({super.key, required this.jobId});"
)

old_button = """              child: ElevatedButton(
                onPressed: () {
                  final dummyJobId = 'JB-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
                  context.push('/checkout/$dummyJobId?partnerId=${state.selectedWorkshop!.id}');
                },"""

new_button = """              child: ElevatedButton(
                onPressed: () async {
                  await ref.read(bookingSchedulingControllerProvider.notifier).assignWorkshopAndDate(jobId);
                  if (context.mounted) {
                    context.push('/checkout/$jobId?partnerId=${state.selectedWorkshop!.id}');
                  }
                },"""

text_booking = text_booking.replace(old_button, new_button)

with io.open(path_booking, 'w', encoding='utf-8') as f:
    f.write(text_booking)

