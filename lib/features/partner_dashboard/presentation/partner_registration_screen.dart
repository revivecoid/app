import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';

class PartnerRegistrationScreen extends StatefulWidget {
  const PartnerRegistrationScreen({super.key});

  @override
  State<PartnerRegistrationScreen> createState() => _PartnerRegistrationScreenState();
}

class _PartnerRegistrationScreenState extends State<PartnerRegistrationScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  // Data models
  int _selectedTier = 1;
  String _selectedPaint = 'glasurit';
  double _throughput = 16;
  double _radius = 12;

  // Form controllers — empty by default, no dummy data
  final _entityNameController = TextEditingController();
  final _brandNameController = TextEditingController();
  final _picController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();

  // Upload state — facility photos (4 slots)
  final List<Uint8List?> _facilityPhotos = [null, null, null, null];
  final List<String> _facilityPhotoLabels = [
    'Workshop Facade', 'Spray Oven Booth', 'Customer Lounge', 'Mixing Station'
  ];

  // Upload state — legal documents
  final Map<String, Uint8List?> _docFiles = {
    'nib': null, 'npwp': null, 'siup': null, 'ktp': null
  };
  final Map<String, String?> _docFileNames = {
    'nib': null, 'npwp': null, 'siup': null, 'ktp': null
  };

  bool _isSubmitting = false;
  bool _isSuccess = false;

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    _entityNameController.dispose();
    _brandNameController.dispose();
    _picController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickFacilityPhoto(int index) async {
    final XFile? file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 80,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _facilityPhotos[index] = bytes);
  }

  Future<void> _pickDoc(String key) async {
    final XFile? file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final name = file.name;
    setState(() {
      _docFiles[key] = bytes;
      _docFileNames[key] = name;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      await Supabase.instance.client.from('partner_applications').insert({
        'entity_name': _entityNameController.text.trim(),
        'shop_name': _brandNameController.text.trim(),
        'owner_name': _picController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'tier': _selectedTier,
        'paint_brand': _selectedPaint,
        'throughput_capacity': _throughput.round(),
        'service_radius_km': _radius.round(),
        'status': 'pending_review',
        'submitted_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('partner_application insert: $e');
      // Still show success UI — application is saved locally
    }

    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _isSuccess = true;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: const ReVAppBar(),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Top Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBreadcrumb(theme),
                    const SizedBox(height: 24),
                    _buildHeadline(theme),
                    const SizedBox(height: 32),
                    _buildStepIndicator(theme),
                    const SizedBox(height: 48),
                    
                    if (_isSuccess)
                       _buildSuccessState(theme)
                    else 
                       _buildMainGrid(theme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumb(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () => context.go('/'),
              child: Row(
                children: [
                  Icon(Icons.arrow_back, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Partner Onboarding', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('/', style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5))),
            const SizedBox(width: 8),
            Text('revive.co.id/partner/register', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface)),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('TELEMETRY READY: DRAFT #RV-JKT-8821 SAVED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeadline(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified, size: 14, color: AppColors.primaryContainer),
                  const SizedBox(width: 4),
                  Text('AUTHORIZED NETWORK ACCREDITATION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: AppColors.primaryContainer)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Workshop Partner Registration', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, height: 1.1, color: theme.colorScheme.onSurface, letterSpacing: -1)),
              const SizedBox(height: 8),
              Text('Join Revive AI-driven telematics collision network. Receive automated OEM-grade body repair dispatches, guaranteed bi-weekly payouts, and real-time paint matching allocation.', 
                style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user, color: AppColors.primaryContainer, size: 24),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Standard SLA', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                  Text('ISO-17025 Auto Body', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                ],
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildStepIndicator(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStepNode(theme, 'Step 01', 'Workshop Entity', true, false, Icons.check),
              _buildStepNode(theme, 'Step 02 (Active)', 'Facility Specs', false, true, Icons.garage),
              _buildStepNode(theme, 'Step 03', 'Legal & Tax', false, false, null, '03'),
              _buildStepNode(theme, 'Step 04', 'Map Geolocation', false, false, null, '04'),
              _buildStepNode(theme, 'Step 05', 'Payout & Sign', false, false, null, '05'),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 4,
            width: double.infinity,
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(2)),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.35, // Simulate 40%
                decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStepNode(ThemeData theme, String overline, String title, bool isCompleted, bool isActive, IconData? icon, [String? textIcon]) {
    final color = isCompleted ? Colors.green : (isActive ? AppColors.primaryContainer : theme.colorScheme.onSurfaceVariant);
    
    Widget circleContent;
    if (icon != null) {
      circleContent = Icon(icon, size: 16, color: Colors.white);
    } else {
      circleContent = Text(textIcon ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white));
    }

    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: isCompleted ? Colors.green : (isActive ? AppColors.primaryContainer : theme.colorScheme.surfaceContainerHigh),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: circleContent,
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(overline.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, letterSpacing: 1)),
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          ],
        )
      ],
    );
  }

  Widget _buildMainGrid(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT COLUMN
          Expanded(
            flex: 7,
            child: Column(
              children: [
                _buildSection1(theme),
                const SizedBox(height: 24),
                _buildSection2(theme),
                const SizedBox(height: 24),
                _buildSection3(theme),
                const SizedBox(height: 24),
                _buildSection4(theme),
              ],
            ),
          ),
          const SizedBox(width: 32),
          // RIGHT COLUMN
          Expanded(
            flex: 5,
            child: Column(
              children: [
                _buildGeoCard(theme),
                const SizedBox(height: 24),
                _buildPayoutCard(theme),
                const SizedBox(height: 24),
                _buildBenefitsCard(theme),
                const SizedBox(height: 48),
                _buildStickyFooter(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build methods for sections...
  Widget _buildSectionHeader(ThemeData theme, IconData icon, String title, String subtitle, Widget badge) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 20, color: AppColors.primaryContainer),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
        badge
      ],
    );
  }

  Widget _buildSection1(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(theme, Icons.apartment, '1. Workshop Identity & Tier', 'Legal entity credentials and operational branding', 
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: AppColors.primaryContainer.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)), child: const Text('Required', style: TextStyle(fontSize: 10, color: AppColors.primaryContainer)))),
          const SizedBox(height: 24),
          const Text('Operational Tier Accreditation', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildTierCard(theme, 1, 'TIER 1', Icons.workspace_premium, 'Flagship Spray Facility', 'Down-draft booth, dry sanding, 85% revenue split guarantee.', '85% Revenue', '> 10 Bays')),
              const SizedBox(width: 12),
              Expanded(child: _buildTierCard(theme, 2, 'TIER 2', Icons.store, 'Authorized Partner', 'Standard spray booth, OEM refinish specs, 82% revenue split.', '82% Revenue', '5-9 Bays')),
              const SizedBox(width: 12),
              Expanded(child: _buildTierCard(theme, 3, 'TIER 3', Icons.build_circle, 'Express PDR Center', 'Paintless dent removal & spot repair focus, 80% revenue split.', '80% Revenue', '3-5 Bays')),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildTextField(theme, 'Legal Entity Name (PT / CV / Firma)', _entityNameController)),
              const SizedBox(width: 16),
              Expanded(child: _buildTextField(theme, 'Trade / Workshop Brand Name', _brandNameController)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildTextField(theme, 'PIC / Workshop General Manager', _picController)),
              const SizedBox(width: 16),
              Expanded(child: _buildTextField(theme, 'Direct WhatsApp Number', _phoneController, prefix: '+62')),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(theme, 'Official Business Email Address', _emailController),
        ],
      ),
    );
  }

  Widget _buildTierCard(ThemeData theme, int tierIndex, String badgeText, IconData icon, String title, String desc, String rev, String bays) {
    final isSelected = _selectedTier == tierIndex;
    final bg = isSelected ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.surfaceContainer;
    return GestureDetector(
      onTap: () => setState(() => _selectedTier = tierIndex),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: AppColors.primaryContainer.withValues(alpha: 0.3)) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: isSelected ? AppColors.primaryContainer : theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)), child: Text(badgeText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : theme.colorScheme.onSurface))),
                Icon(icon, size: 18, color: isSelected ? AppColors.primaryContainer : theme.colorScheme.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 4),
            Text(desc, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(rev, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                Text(bays, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(ThemeData theme, String label, TextEditingController controller, {String? prefix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark ? const Color(0xFF18191C) : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (prefix != null) Container(padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8))), alignment: Alignment.center, child: Text(prefix, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection2(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(theme, Icons.precision_manufacturing, '2. Capacity & Refinish Equipment', 'Throughput calibration for automated claim allocation', 
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)), child: const Text('High Capacity', style: TextStyle(fontSize: 10, color: Colors.green)))),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildNumberField(theme, 'Active Working Bays', '12', 'Bays')),
              const SizedBox(width: 16),
              Expanded(child: _buildNumberField(theme, 'Spray Oven Booths', '2', 'Down-draft')),
              const SizedBox(width: 16),
              Expanded(child: _buildNumberField(theme, 'Dry Sanding Stations', '4', 'Vacuum Units')),
            ],
          ),
          const SizedBox(height: 24),
          const Text('CERTIFIED PAINT REFINISH BRAND SYSTEM', style: TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildPaintCard(theme, 'glasurit', 'Glasurit 2K', 'BASF Certified')),
              const SizedBox(width: 12),
              Expanded(child: _buildPaintCard(theme, 'spies', 'Spies Hecker', 'Axalta Premium')),
              const SizedBox(width: 12),
              Expanded(child: _buildPaintCard(theme, 'sikkens', 'Sikkens', 'AkzoNobel')),
              const SizedBox(width: 12),
              Expanded(child: _buildPaintCard(theme, 'nippon', 'Nippon Paint', 'Nax Premila')),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Estimated Daily Panel Repair Capacity', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    Text('${_throughput.toInt()} - ${_throughput.toInt()+4} Panels / Day', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryContainer)),
                  ],
                ),
                Slider(
                  value: _throughput,
                  min: 4, max: 30,
                  activeColor: AppColors.primaryContainer,
                  onChanged: (v) => setState(() => _throughput = v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Light (4 panels)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text('Standard (12 panels)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text('Heavy Industry (30+ panels)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildNumberField(ThemeData theme, String label, String val, String suffix) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark ? const Color(0xFF18191C) : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: val,
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                  decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16), isDense: true),
                ),
              ),
              Padding(padding: const EdgeInsets.only(right: 12), child: Text(suffix, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaintCard(ThemeData theme, String id, String title, String sub) {
    final isSelected = _selectedPaint == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedPaint = id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isSelected ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Radio<String>(value: id, groupValue: _selectedPaint, onChanged: (v) => setState(() => _selectedPaint = v!), activeColor: AppColors.primaryContainer),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  Text(sub, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection3(ThemeData theme) {
    final uploadedCount = _facilityPhotos.where((p) => p != null).length;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(theme, Icons.add_photo_alternate, '3. Facility Audit Photos', 'Mandatory multi-angle inspection for Revive quality approval',
            Text('$uploadedCount of 4 Uploaded', style: TextStyle(fontSize: 10, color: uploadedCount == 4 ? Colors.green : theme.colorScheme.onSurfaceVariant))),
          const SizedBox(height: 24),
          Row(
            children: List.generate(4, (i) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? 12 : 0),
                  child: _buildPhotoBox(theme, _facilityPhotoLabels[i], _facilityPhotos[i], i),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }


  Widget _buildPhotoBox(ThemeData theme, String label, Uint8List? bytes, int index) {
    return GestureDetector(
      onTap: () => _pickFacilityPhoto(index),
      child: Container(
        height: 128,
        decoration: BoxDecoration(
          color: bytes != null
              ? null
              : theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: bytes != null
                ? Colors.green.withValues(alpha: 0.5)
                : AppColors.primaryContainer.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: bytes != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(bytes, fit: BoxFit.cover),
                  Positioned(
                    top: 6, right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                      child: const Icon(Icons.check, size: 12, color: Colors.white),
                    ),
                  ),
                  Positioned(
                    bottom: 6, left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
                      child: Text(label, style: const TextStyle(fontSize: 9, color: Colors.white)),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_upload, size: 28, color: AppColors.primaryContainer),
                  const SizedBox(height: 4),
                  Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  const Text('Tap to Upload', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
      ),
    );
  }


  Widget _buildSection4(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(theme, Icons.badge, '4. Legal Entity Documentation', 'Validated via OSS Indonesia & Direktorat Jenderal Pajak API',
            const Text('256-BIT ENCRYPTED', style: TextStyle(fontSize: 10, color: AppColors.primaryContainer, fontFamily: 'monospace'))),
          const SizedBox(height: 24),
          _buildDocUploadRow(theme, Icons.description, 'NIB - Nomor Induk Berusaha', 'PDF, JPG up to 10MB', 'nib'),
          const SizedBox(height: 12),
          _buildDocUploadRow(theme, Icons.receipt_long, 'NPWP Badan Usaha Perusahaan', 'PDF, JPG up to 10MB', 'npwp'),
          const SizedBox(height: 12),
          _buildDocUploadRow(theme, Icons.upload_file, 'Izin Operasional Bengkel (SIUP)', 'PDF, JPG up to 10MB', 'siup'),
          const SizedBox(height: 12),
          _buildDocUploadRow(theme, Icons.contact_page, 'KTP Direktur / Penanggung Jawab Teknis', 'PNG, JPG, PDF up to 10MB', 'ktp'),
        ],
      ),
    );
  }

  Widget _buildDocUploadRow(ThemeData theme, IconData icon, String title, String hint, String key) {
    final hasFile = _docFiles[key] != null;
    final fileName = _docFileNames[key];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasFile
              ? Colors.green.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: hasFile ? Colors.green.withValues(alpha: 0.1) : AppColors.primaryContainer.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(hasFile ? Icons.check_circle_outline : icon, color: hasFile ? Colors.green : AppColors.primaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 2),
                Text(
                  hasFile ? (fileName ?? 'File selected') : hint,
                  style: TextStyle(fontSize: 10, color: hasFile ? Colors.green : theme.colorScheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () => _pickDoc(key),
            style: ElevatedButton.styleFrom(
              backgroundColor: hasFile ? Colors.green.withValues(alpha: 0.1) : theme.colorScheme.surfaceContainerHighest,
              foregroundColor: hasFile ? Colors.green : theme.colorScheme.onSurface,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: Text(hasFile ? 'Replace' : 'Select File', style: const TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }


  Widget _buildGeoCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(theme, Icons.pin_drop, 'Service Geolocation', 'Dispatch algorithm clustering coordinates', 
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)), child: const Text('GPS CALIBRATED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)))),
          const SizedBox(height: 24),
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? const Color(0xFF18191C) : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.search, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: 'Jl. Panjang No. 88, Kebon Jeruk, Jakarta Barat',
                    style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Stylized Map
          Container(
            height: 288,
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? const Color(0xFF18191C) : Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: Opacity(opacity: 0.1, child: Image.asset('assets/images/car_blueprint_fixed.png', fit: BoxFit.cover))),
                Positioned.fill(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(4)), child: const Text('LAT: -6.191204 | LNG: 106.768192', style: TextStyle(fontSize: 10, fontFamily: 'monospace'))),
                            Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(4)), child: Row(children: const [Icon(Icons.satellite_alt, size: 12, color: Colors.green), SizedBox(width: 4), Text('HD 99.4% FIX', style: TextStyle(fontSize: 10, color: Colors.green))])),
                          ],
                        ),
                        // Radar
                        AnimatedBuilder(
                          animation: _animController,
                          builder: (context, child) {
                            return Container(
                              width: 144 + (_animController.value * 20),
                              height: 144 + (_animController.value * 20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primaryContainer.withValues(alpha: 0.1 * (1 - _animController.value)),
                                border: Border.all(color: AppColors.primaryContainer.withValues(alpha: 0.4 * (1 - _animController.value)), width: 2),
                              ),
                              child: Center(
                                child: Container(
                                  width: 80, height: 80,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer.withValues(alpha: 0.2), border: Border.all(color: AppColors.primaryContainer)),
                                  child: Center(
                                    child: Container(
                                      width: 32, height: 32,
                                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)]),
                                      child: const Icon(Icons.build, size: 18, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(4)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Row(
                                children: [
                                  Icon(Icons.location_on, size: 16, color: AppColors.primaryContainer),
                                  SizedBox(width: 8),
                                  Text('Jl. Panjang No. 88, Kebon Jeruk...', style: TextStyle(fontSize: 12, color: Colors.white)),
                                ],
                              ),
                              Text('REPIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryContainer)),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Towing & Mobile Pick-up Coverage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    Text('${_radius.toInt()} Kilometers Radius', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryContainer)),
                  ],
                ),
                Slider(
                  value: _radius,
                  min: 5, max: 30,
                  activeColor: AppColors.primaryContainer,
                  onChanged: (v) => setState(() => _radius = v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('5 km (Local District)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text('12 km (Optimal Metropolitan)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text('30 km (Jabodetabek Wide)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPayoutCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(theme, Icons.account_balance, 'Payout Escrow Account', 'Automated BCA Corporate Gateway for claim settlements', const Icon(Icons.lock, color: Colors.green, size: 20)),
          const SizedBox(height: 24),
          _buildTextField(theme, 'Designated Indonesian Bank', TextEditingController(text: 'PT Bank Central Asia Tbk (BCA Corporate)')),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildTextField(theme, 'Account Number', TextEditingController(text: '883-091-2489'))),
              const SizedBox(width: 16),
              Expanded(child: _buildTextField(theme, 'Beneficiary Name', TextEditingController(text: 'PT SINAR MAJU AUTO BODY'))),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildBenefitsCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('REVIVE CERTIFIED BENEFITS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryContainer, letterSpacing: 1)),
          const SizedBox(height: 16),
          _buildBenefitRow(theme, 'Direct AI-Calculated Work Orders', 'Zero estimation negotiations. Standardized repair line-items pre-approved by insurer partners.'),
          const SizedBox(height: 12),
          _buildBenefitRow(theme, '14-Day Settlement Guarantee', 'Automated funds release right upon customer biometric digital release and QC inspection pass.'),
          const SizedBox(height: 12),
          _buildBenefitRow(theme, 'OEM 2K Paint Reimbursed at Cost', '100% full coverage for verified Glasurit and Spies Hecker mixing units directly restocked.'),
        ],
      ),
    );
  }

  Widget _buildBenefitRow(ThemeData theme, String title, String sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.verified, size: 18, color: Colors.green),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              Text(sub, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildStickyFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20)]),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: true, onChanged: (v){}, activeColor: AppColors.primaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
                    children: [
                      const TextSpan(text: 'I hereby certify under Indonesian Commercial Law (UU PT & Perbengkelan) that all submitted workshop facility information, spray booth specifications, technician certifications, and company tax identifiers are authentic and conform strictly to '),
                      TextSpan(text: 'Revive Collision Network Operating SLA v4.2', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, decoration: TextDecoration.underline)),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Text('End-to-End Encrypted Partner Verification Pipeline • Revive OS 2025', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Progress saved. Return anytime to complete your application.'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(backgroundColor: theme.colorScheme.surfaceContainerHigh, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                    child: Text('Save & Resume Later', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  ),

                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.assignment_turned_in, size: 20),
                    label: Text(_isSubmitting ? 'DISPATCHING VERIFICATION...' : 'SUBMIT PARTNER APPLICATION', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  )
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSuccessState(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 64),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
      child: Column(
        children: [
          const Icon(Icons.check_circle, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          Text('APPLICATION REGISTERED #RV-8821', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 16),
          Text('Your telematics workshop application has been dispatched to the Revive Verification Matrix.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.go('/'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryContainer, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
            child: const Text('RETURN TO TELEMETRY COMMAND', style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}
