import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/widgets/responsive_layout_guard.dart';
import '../../../../core/widgets/rev_app_bar.dart';
import '../../../../core/theme/app_theme.dart';
import 'checkout_payment_controller.dart';

class CheckoutPaymentScreen extends ConsumerStatefulWidget {
  final String jobId;
  final String partnerId;

  const CheckoutPaymentScreen({
    super.key,
    required this.jobId,
    required this.partnerId,
  });

  @override
  ConsumerState<CheckoutPaymentScreen> createState() => _CheckoutPaymentScreenState();
}

class _CheckoutPaymentScreenState extends ConsumerState<CheckoutPaymentScreen> {
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isFetchingLocation = false;

  @override
  void dispose() {
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _fetchDeviceLocation() async {
    setState(() => _isFetchingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.')));
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are denied.')));
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are permanently denied, we cannot request permissions.')));
        return;
      } 

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _latController.text = position.latitude.toString();
        _lngController.text = position.longitude.toString();
      });
      _submitLocationDetails();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching location: $e')));
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  void _submitLocationDetails() {
    if (_formKey.currentState!.validate()) {
      final lat = double.tryParse(_latController.text);
      final lng = double.tryParse(_lngController.text);
      ref.read(checkoutControllerProvider(widget.jobId).notifier)
         .setPickupLocation(_addressController.text, lat, lng);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checkoutControllerProvider(widget.jobId));
    final controller = ref.read(checkoutControllerProvider(widget.jobId).notifier);

    // Defensive structural listener for error states and network webhook confirmations
    ref.listen<CheckoutState>(checkoutControllerProvider(widget.jobId), (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!), backgroundColor: AppColors.fireRed),
        );
      }
      if (next.paymentStatus == PaymentStatus.paid && previous?.paymentStatus != PaymentStatus.paid) {
        _showSuccessDialog('Payment Confirmed', 'Your transaction has been verified via the backend webhook. The workshop schedule is now booked.');
      } else if (next.paymentStatus == PaymentStatus.manualTransferPending && previous?.paymentStatus != PaymentStatus.manualTransferPending) {
        _showSuccessDialog('Booking Confirmed', 'Please complete your bank transfer. Our admins will verify your payment shortly.');
      }
    });

    final checkoutForm = SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Logistics Configuration', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          
          // STRICT REQUIREMENT 3: LOGISTICS STATE MACHINE
          SegmentedButton<DeliveryOption>(
            segments: const [
              ButtonSegment(value: DeliveryOption.selfDeliver, label: Text('Self Delivery'), icon: Icon(Icons.directions_car)),
              ButtonSegment(value: DeliveryOption.pickup, label: Text('Valet Pickup'), icon: Icon(Icons.person_pin_circle)),
            ],
            selected: {state.deliveryOption},
            onSelectionChanged: (Set<DeliveryOption> newSelection) {
              controller.setDeliveryOption(newSelection.first);
            },
            style: ButtonStyle(
              backgroundColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
                if (states.contains(MaterialState.selected)) return AppColors.fireRed;
                return Colors.transparent;
              }),
            ),
          ),
          const SizedBox(height: 24),

          // Dynamic Pickup Fields requiring string and lat/lng validation
          if (state.deliveryOption == DeliveryOption.pickup)
            Form(
              key: _formKey,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.daysGray),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pickup Location Details', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(labelText: 'Full Street Address', border: OutlineInputBorder()),
                      validator: (value) {
                        if (value == null || value.trim().length < 10) return 'Please enter a complete address (min 10 chars)';
                        return null;
                      },
                      onChanged: (_) => _submitLocationDetails(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _latController,
                            decoration: const InputDecoration(labelText: 'Latitude', border: OutlineInputBorder()),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) return null;
                              if (double.tryParse(value) == null) return 'Invalid';
                              return null;
                            },
                            onChanged: (_) => _submitLocationDetails(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _lngController,
                            decoration: const InputDecoration(labelText: 'Longitude', border: OutlineInputBorder()),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) return null;
                              if (double.tryParse(value) == null) return 'Invalid';
                              return null;
                            },
                            onChanged: (_) => _submitLocationDetails(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.fireRed.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            icon: _isFetchingLocation 
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.fireRed)) 
                                : const Icon(Icons.my_location, color: AppColors.fireRed),
                            onPressed: _isFetchingLocation ? null : _fetchDeviceLocation,
                            tooltip: 'Get Device Location',
                          ),
                        )
                      ],
                    ),
                  ],
                ),
              ),
            ),
          
          const SizedBox(height: 32),
          
          // STRICT REQUIREMENT 4: CALENDAR SCHEDULER
          Text('Schedule Intake Date', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: CalendarDatePicker(
              initialDate: state.scheduledDate ?? DateTime.now().add(const Duration(days: 1)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 60)),
              onDateChanged: (DateTime date) async {
                await controller.checkAndSetScheduledDate(date, widget.partnerId);
              },
            ),
          ),
          if (state.scheduledDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                'Verified Intake Date: ${state.scheduledDate!.toLocal().toString().split(' ')[0]}',
                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
              ),
            ),

          const SizedBox(height: 32),

          Text('Payment Method', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          SegmentedButton<PaymentMethod>(
            segments: const [
              ButtonSegment(value: PaymentMethod.onlineGateway, label: Text('Online / QR / VA'), icon: Icon(Icons.qr_code_scanner)),
              ButtonSegment(value: PaymentMethod.manualTransfer, label: Text('Bank Transfer'), icon: Icon(Icons.account_balance)),
            ],
            selected: {state.paymentMethod},
            onSelectionChanged: (Set<PaymentMethod> newSelection) {
              controller.setPaymentMethod(newSelection.first);
            },
            style: ButtonStyle(
              backgroundColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
                if (states.contains(MaterialState.selected)) return AppColors.fireRed;
                return Colors.transparent;
              }),
            ),
          ),
          if (state.paymentMethod == PaymentMethod.manualTransfer) ...[
            const SizedBox(height: 24),
            Text('Transfer Proof', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.daysGray.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  if (state.transferProof != null) ...[
                    const Icon(Icons.check_circle, color: Colors.green, size: 48),
                    const SizedBox(height: 8),
                    Text('Proof Selected: ${state.transferProof!.name}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                  ] else ...[
                    const Icon(Icons.cloud_upload, color: AppColors.daysGray, size: 48),
                    const SizedBox(height: 8),
                    const Text('Please upload an image of your transfer receipt.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.daysGray)),
                    const SizedBox(height: 16),
                  ],
                  ElevatedButton.icon(
                    onPressed: () async {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        controller.setTransferProof(image);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.fireRed,
                      side: const BorderSide(color: AppColors.fireRed),
                    ),
                    icon: const Icon(Icons.upload_file),
                    label: Text(state.transferProof != null ? 'Change File' : 'Upload Proof'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    // STRICT REQUIREMENT 2 & 5: Persistent Pricing Panel and Payment Integration
    final pricingPanel = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.daysGray.withValues(alpha: 0.5))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('AI Estimate Summary', style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            'IDR ${state.estimatedCost.toStringAsFixed(2)}', 
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)
          ),
          const SizedBox(height: 8),
          if (state.deliveryOption == DeliveryOption.pickup)
            const Text('+ Valet Service Fee Applicable', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: state.isLoading || state.paymentStatus == PaymentStatus.awaitingWebhook
                ? null 
                : () {
                    if (state.deliveryOption == DeliveryOption.pickup && !_formKey.currentState!.validate()) {
                      return; // Block UI from advancing if validations fail
                    }
                    controller.executePaymentAndBooking();
                  },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 20),
              backgroundColor: AppColors.fireRed,
            ),
            child: state.isLoading 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : state.paymentStatus == PaymentStatus.awaitingWebhook
                    ? const Text('Awaiting Gateway Webhook...', style: TextStyle(color: Colors.white))
                    : Text(state.paymentMethod == PaymentMethod.manualTransfer ? 'CONFIRM BOOKING (TRANSFER)' : 'PAY NOW (QR / VA)', style: const TextStyle(fontSize: 16, letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );

    // STRICT REQUIREMENT 2: Responsive Layout implementation
    return Scaffold(
      appBar: ReVAppBar(title: const Text('Checkout & Booking')),
      body: ResponsiveLayoutGuard(
        mobileWidget: Column(
          children: [
            Expanded(child: checkoutForm),
            pricingPanel,
          ],
        ),
        desktopWidget: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: checkoutForm),
            Container(width: 1, color: AppColors.daysGray),
            Expanded(
              flex: 2, 
              child: Align(
                alignment: Alignment.topCenter,
                child: pricingPanel
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog(String title, String content) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
          ],
        ),
        content: Text(
          content,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              context.go('/track/${widget.jobId}');
            },
            child: const Text('View Repair Tracker'),
          ),
        ],
      ),
    );
  }
}
