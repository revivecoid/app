import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/image_compressor.dart';
import '../providers/panel_selection_provider.dart';
import '../providers/customer_intake_provider.dart';
import 'widgets/interactive_car_diagram.dart';
import '../../../../core/widgets/rev_app_bar.dart';

import '../../../../core/theme/app_theme.dart';

class EstimatorScreen extends ConsumerStatefulWidget {
  const EstimatorScreen({super.key});

  @override
  ConsumerState<EstimatorScreen> createState() => _EstimatorScreenState();
}

class _EstimatorScreenState extends ConsumerState<EstimatorScreen> {
  static const Map<String, List<String>> _carDatabase = {
    'Toyota': ['Avanza', 'Innova', 'Fortuner', 'Agya', 'Calya', 'Yaris', 'Rush', 'Camry', 'Corolla'],
    'Honda': ['Brio', 'HR-V', 'CR-V', 'BR-V', 'City', 'Civic', 'Mobilio', 'Accord', 'Jazz'],
    'Daihatsu': ['Sigra', 'Ayla', 'Xenia', 'Terios', 'Gran Max', 'Sirion'],
    'Suzuki': ['Ertiga', 'XL7', 'Ignis', 'Baleno', 'Jimny', 'Swift'],
    'Mitsubishi': ['Xpander', 'Pajero Sport', 'Outlander', 'Triton'],
    'Nissan': ['Livina', 'Serena', 'X-Trail', 'Magnite', 'Kicks'],
    'Hyundai': ['Creta', 'Stargazer', 'Palisade', 'Santa Fe', 'Ioniq 5', 'Ioniq 6'],
    'Kia': ['Sonet', 'Seltos', 'Carnival', 'Carens'],
    'Mazda': ['CX-3', 'CX-5', 'CX-30', 'Mazda 2', 'Mazda 3'],
    'Wuling': ['Air EV', 'Almaz', 'Confero', 'Cortez', 'Binguo'],
    'Other': [],
  };

  int _currentStep = 0;
  final _formKey = GlobalKey<FormState>();
  
  // Contact
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  
  // Demographics
  String? _selectedMake;
  String? _selectedModel;
  late TextEditingController _customMakeController;
  late TextEditingController _customModelController;
  late TextEditingController _yearController;
  late TextEditingController _licensePlateController;

  // Visual Intake
  XFile? _selectedImage;
  bool _isAnalyzing = false;
  String? _aiResult;
  Map<String, dynamic>? _structuredData;

  @override
  void initState() {
    super.initState();
    final intake = ref.read(customerIntakeProvider);
    _nameController = TextEditingController(text: intake.name);
    _phoneController = TextEditingController(text: intake.phone);
    
    _selectedMake = (_carDatabase.containsKey(intake.brand) || intake.brand.isEmpty) ? (intake.brand.isEmpty ? null : intake.brand) : 'Other';
    _customMakeController = TextEditingController(text: _selectedMake == 'Other' ? intake.brand : '');
    
    if (_selectedMake != null && _selectedMake != 'Other' && _carDatabase[_selectedMake]!.contains(intake.model)) {
      _selectedModel = intake.model;
    } else if (intake.model.isNotEmpty) {
      _selectedModel = 'Other';
    }
    _customModelController = TextEditingController(text: _selectedModel == 'Other' ? intake.model : '');
    
    _yearController = TextEditingController(text: intake.year);
    _licensePlateController = TextEditingController(text: intake.licensePlate);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _customMakeController.dispose();
    _customModelController.dispose();
    _yearController.dispose();
    _licensePlateController.dispose();
    super.dispose();
  }

  Future<void> _captureImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() => _selectedImage = image);
    }
  }

  Future<void> _submitToVisionAi() async {
    if (_selectedImage == null) return;
    
    setState(() {
      _isAnalyzing = true;
      _aiResult = null;
    });

    try {
      final compressedBytes = await ImageCompressor.compressImage(_selectedImage!);
      
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Supabase.instance.client.storage
          .from('revive-photos')
          .uploadBinary(fileName, compressedBytes);
          
      final publicUrl = Supabase.instance.client.storage.from('revive-photos').getPublicUrl(fileName);
      
      final selectedPanels = ref.read(selectedPanelsProvider);
      final selectedPanelLabels = selectedPanels.map((p) => p.label).toList();

      final res = await Supabase.instance.client.functions.invoke(
        'vision-estimation',
        body: {
          'photoUrl': publicUrl, 
          'damageDescription': 'User uploaded car damage',
          'selectedPanels': selectedPanelLabels
        },
      );

      setState(() {
        _aiResult = res.data['estimation'] ?? 'AI categorization complete.';
        _structuredData = res.data['structuredData'];
        if (_structuredData != null) {
          final cost = _structuredData!['financial_estimation']?['calculated_base_cost'] ?? 0;
          ref.read(customerIntakeProvider.notifier).updateEstimatedCost((cost as num).toDouble());
        }
      });

    } catch (e) {
      setState(() {
        _aiResult = 'Estimation Engine Fallback Triggered. Error: $e';
      });
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  String _formatCurrency(dynamic amount) {
    if (amount == null) return '0';
    final str = amount.toString().split('.')[0];
    String res = '';
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && i % 3 == 0) {
        res = '.$res';
      }
      res = str[str.length - 1 - i] + res;
    }
    return res;
  }

  void _onNextStep() async {
    if (_currentStep == 0) {
      if (_aiResult == null) {
        if (_selectedImage != null && ref.read(selectedPanelsProvider).isNotEmpty) {
          _submitToVisionAi();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please capture an image and select panels before continuing.')),
          );
        }
      } else {
        setState(() => _currentStep += 1);
      }
    } else if (_currentStep < 3) {
      setState(() => _currentStep += 1);
    } else {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in or create an account to secure your booking.')));
        context.push('/login?returnTo=/estimator');
        return;
      }
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(child: CircularProgressIndicator(color: AppColors.fireRed)),
      );

      try {
        final intake = ref.read(customerIntakeProvider);
        
        final vehicleRes = await Supabase.instance.client.from('vehicles').insert({
          'customer_id': user.id,
          'make': intake.brand,
          'model': intake.model,
          'year': int.tryParse(intake.year) ?? 2020,
          'license_plate': intake.licensePlate,
        }).select('id').single();
        
        final jobRes = await Supabase.instance.client.from('repair_jobs').insert({
          'customer_id': user.id,
          'vehicle_id': vehicleRes['id'],
          'initial_estimation_cost': intake.estimatedCost,
          'status': '2_estimated',
          'service_area': intake.location.isEmpty ? null : intake.location,
        }).select('id').single();
        
        if (context.mounted) {
          Navigator.of(context).pop();
          context.push('/booking/schedule/${jobRes['id']}');
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error securing booking: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Widget _buildProgressSteps() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceContainerLowest : Colors.white),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.lens, color: AppColors.fireRed, size: 15),
                  SizedBox(width: 4),
                  Text(
                    'STEP ${_currentStep + 1} OF 4: ${_getStepTitle()}',
                    style: TextStyle(
                      color: AppColors.fireRed,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              Text(
                '${((_currentStep + 1) * 25).toInt()}%',
                style: TextStyle(
                  color: AppColors.fireRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: List.generate(4, (index) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: index < 3 ? 6 : 0),
                  height: 6,
                  decoration: BoxDecoration(
                    color: index <= _currentStep ? AppColors.fireRed : (isDark ? AppColors.surfaceContainer : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              _buildStepLabel('Damage', 'Active', 0),
              _buildStepLabel('Vehicle', 'Step 2', 1),
              _buildStepLabel('Contact', 'Step 3', 2),
              _buildStepLabel('Confirm', 'Step 4', 3),
            ],
          ),
        ],
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0: return 'VISUAL DAMAGE INTAKE';
      case 1: return 'VEHICLE DEMOGRAPHICS';
      case 2: return 'CONTACT DETAILS';
      case 3: return 'BOOKING CONFIRMATION';
      default: return '';
    }
  }

  Widget _buildStepLabel(String title, String subtitle, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = index == _currentStep;
    final isPast = index < _currentStep;
    final textColor = isActive || isPast ? (isDark ? AppColors.onSurface : Colors.black87) : (isDark ? AppColors.onSurfaceVariant : Colors.black54);
    final subColor = isActive ? AppColors.fireRed : (isDark ? AppColors.onSurfaceVariant : Colors.black54);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: textColor,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: subColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceContainerLow : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.fireRed.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.info, color: AppColors.fireRed, size: 18),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vehicle Scan & Damage Triage',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Colors.black87)),
                ),
                SizedBox(height: 4),
                Text(
                  'Provide a photo of the damage and select affected panels on the digital twin.\nNote: Make sure to clearly capture any scratches (gores) or dents (penyok).',
                  style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoUpload() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceContainerLowest : Colors.white),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'INTAKE IMAGERY',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: (isDark ? AppColors.onSurfaceVariant : Colors.black54),
                ),
              ),
              if (_aiResult != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.fireRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'AI Verified',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.fireRed),
                  ),
                ),
            ],
          ),
          SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _captureImage,
            icon: Icon(Icons.photo_camera, size: 20),
            label: Text('Capture Damage Photo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.fireRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 1,
            ),
          ),
          if (_selectedImage != null) ...[
            SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: (isDark ? AppColors.surfaceContainerLow : Colors.grey.shade50),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: (isDark ? AppColors.surfaceContainer : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Center(child: Icon(Icons.image, color: Colors.grey)),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 16),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _selectedImage!.name,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Colors.black87)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text('High-res inspection • Selected', style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54))),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.sync, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54)),
                    onPressed: _captureImage,
                  )
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildDigitalTwin() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceContainerLowest : Colors.white),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Digital Twin Analysis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Colors.black87))),
                  Text('Tap to select affected panels', style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isDark ? AppColors.surfaceContainer : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.fireRed, shape: BoxShape.circle)),
                    SizedBox(width: 4),
                    Text('Live Twin', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Colors.black87))),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: (isDark ? AppColors.surfaceContainerLow : Colors.grey.shade50),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            child: AspectRatio(
              aspectRatio: 938.0 / 610.0,
              child: InteractiveCarDiagram(
                selectedPanels: ref.watch(selectedPanelsProvider),
                onToggle: (panel) {
                  ref.read(selectedPanelsProvider.notifier).togglePanel(panel);
                },
              ),
            ),
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ref.watch(selectedPanelsProvider).map((panel) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (isDark ? AppColors.surfaceContainer : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, color: AppColors.fireRed, size: 16),
                    SizedBox(width: 4),
                    Text(panel.label, style: TextStyle(color: AppColors.fireRed, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDamageAssessmentReport() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_aiResult == null) return const SizedBox.shrink();

    final panels = (_structuredData != null && _structuredData!['assessment'] != null)
        ? (_structuredData!['assessment']['damaged_panels_detail'] as List<dynamic>? ?? [])
        : [];
    final totalCost = _structuredData?['financial_estimation']?['calculated_base_cost'] ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceContainerLowest : Colors.white),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.surfaceContainerLow : Colors.grey.shade50),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.fireRed,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.assignment_turned_in, color: Colors.white, size: 20),
                    ),
                    SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Damage Assessment Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Colors.black87))),
                        Text('Computer Vision Triage Matrix', style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54))),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isDark ? AppColors.surfaceContainer : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('${panels.length} Items', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.fireRed)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (panels.isEmpty)
                  Text('Assessment:\n$_aiResult', style: TextStyle(color: (isDark ? AppColors.onSurface : Colors.black87))),
                ...panels.map((panel) {
                  final severity = (panel['panel_severity']?.toString() ?? 'ringan').toUpperCase();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (isDark ? AppColors.surfaceContainerLow : Colors.grey.shade50),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(panel['panel_name']?.toString() ?? '-', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Colors.black87))),
                            Text('Rp ${_formatCurrency(panel['calculated_cost'] ?? 0)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Colors.black87))),
                          ],
                        ),
                        SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Observasi: ', style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54))),
                            Expanded(
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  if ((panel['scratches_found'] as num? ?? 0) > 0)
                                    Text('⚡ Gores', style: TextStyle(fontSize: 12, color: Colors.orange[700], fontWeight: FontWeight.bold)),
                                  if ((panel['scratches_found'] as num? ?? 0) > 0 && (panel['dents_found'] as num? ?? 0) > 0)
                                    Text(' • ', style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54))),
                                  if ((panel['dents_found'] as num? ?? 0) > 0)
                                    Text('🔨 Penyok', style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.bold)),
                                  if ((panel['scratches_found'] as num? ?? 0) == 0 && (panel['dents_found'] as num? ?? 0) == 0)
                                    Text('Kerusakan Umum', style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54))),
                                ],
                              ),
                            ),
                            SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.fireRed.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Severity: $severity', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.fireRed)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
                SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isDark ? AppColors.surfaceContainer : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TOTAL ESTIMATION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54))),
                          Text('Includes Color Matching & Clear Coat', style: TextStyle(fontSize: 11, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54))),
                        ],
                      ),
                      Text('Rp ${_formatCurrency(totalCost)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.fireRed)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: _selectedMake,
          decoration: const InputDecoration(labelText: 'Car Brand'),
          items: _carDatabase.keys.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (val) {
            setState(() {
              _selectedMake = val;
              _selectedModel = null;
              _customMakeController.clear();
              _customModelController.clear();
            });
            if (val != null && val != 'Other') {
              ref.read(customerIntakeProvider.notifier).updateBrand(val);
            }
          },
        ),
        if (_selectedMake == 'Other')
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: TextFormField(
              controller: _customMakeController,
              decoration: const InputDecoration(labelText: 'Enter Car Brand'),
              onChanged: (val) => ref.read(customerIntakeProvider.notifier).updateBrand(val),
            ),
          ),
        SizedBox(height: 12),
        if (_selectedMake != null && _selectedMake != 'Other')
          DropdownButtonFormField<String>(
            value: _selectedModel,
            decoration: const InputDecoration(labelText: 'Car Model'),
            items: [..._carDatabase[_selectedMake]!, 'Other'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) {
              setState(() {
                _selectedModel = val;
                _customModelController.clear();
              });
              if (val != null && val != 'Other') {
                ref.read(customerIntakeProvider.notifier).updateModel(val);
              }
            },
          ),
        if (_selectedMake == 'Other' || _selectedModel == 'Other')
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: TextFormField(
              controller: _customModelController,
              decoration: const InputDecoration(labelText: 'Enter Car Model'),
              onChanged: (val) => ref.read(customerIntakeProvider.notifier).updateModel(val),
            ),
          ),
        SizedBox(height: 12),
        TextFormField(
          controller: _yearController,
          decoration: const InputDecoration(labelText: 'Year of Production'),
          keyboardType: TextInputType.number,
          onChanged: (val) => ref.read(customerIntakeProvider.notifier).updateYear(val),
        ),
        SizedBox(height: 12),
        TextFormField(
          controller: _licensePlateController,
          decoration: const InputDecoration(labelText: 'License Plate (e.g. B 1234 XYZ)'),
          textCapitalization: TextCapitalization.characters,
          onChanged: (val) => ref.read(customerIntakeProvider.notifier).updateLicensePlate(val),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Full Name'),
            onChanged: (val) => ref.read(customerIntakeProvider.notifier).updateName(val),
          ),
          SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: 'WhatsApp Number'),
            keyboardType: TextInputType.phone,
            onChanged: (val) => ref.read(customerIntakeProvider.notifier).updatePhone(val),
          ),
          SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: 'Select Service Area'),
            value: ref.watch(customerIntakeProvider).location.isEmpty ? null : ref.watch(customerIntakeProvider).location,
            items: [
              'Bandung', 'Cimahi', 'Soreang', 
              'Jakarta Pusat', 'Jakarta Utara', 'Jakarta Timur', 'Jakarta Selatan', 'Jakarta Barat', 
              'Bogor', 'Depok', 'Tangerang', 'Bekasi'
            ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) {
              if (val != null) {
                ref.read(customerIntakeProvider.notifier).updateLocation(val);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStep4() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final intake = ref.watch(customerIntakeProvider);
    final panels = (_structuredData != null && _structuredData!['assessment'] != null)
        ? (_structuredData!['assessment']['damaged_panels_detail'] as List<dynamic>? ?? [])
        : [];
    final totalCost = _structuredData?['financial_estimation']?['calculated_base_cost'] ?? 0;
    final overallSeverity = _structuredData?['assessment']?['severity_classification'] ?? '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header notice
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.fireRed.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.fireRed.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_outlined, color: AppColors.fireRed, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Review your details before confirming. Go back to edit anything.',
                  style: TextStyle(fontSize: 13, color: (isDark ? AppColors.onSurface : Colors.black87)),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),

        // ── Section 1: Contact ──────────────────────────────────────
        _buildReviewSection(
          icon: Icons.person_outline,
          title: 'Contact Details',
          rows: [
            _ReviewRow('Full Name', intake.name.isEmpty ? '—' : intake.name),
            _ReviewRow('WhatsApp', intake.phone.isEmpty ? '—' : intake.phone),
            _ReviewRow('Service Area', intake.location.isEmpty ? '—' : intake.location),
          ],
        ),
        SizedBox(height: 12),

        // ── Section 2: Vehicle ──────────────────────────────────────
        _buildReviewSection(
          icon: Icons.directions_car_outlined,
          title: 'Vehicle Details',
          rows: [
            _ReviewRow('Brand', intake.brand.isEmpty ? '—' : intake.brand),
            _ReviewRow('Model', intake.model.isEmpty ? '—' : intake.model),
            _ReviewRow('Year', intake.year.isEmpty ? '—' : intake.year),
            _ReviewRow('License Plate', intake.licensePlate.isEmpty ? '—' : intake.licensePlate),
          ],
        ),
        SizedBox(height: 12),

        // ── Section 3: Damage Assessment ────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: (isDark ? AppColors.surfaceContainerLowest : Colors.white),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
          ),
          child: Column(
            children: [
              // section header
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: (isDark ? AppColors.surfaceContainerLow : Colors.grey.shade50),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.assignment_turned_in_outlined, size: 18, color: AppColors.fireRed),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Damage Assessment',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Colors.black87)),
                      ),
                    ),
                    if (overallSeverity != '-')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.fireRed.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Overall: ${overallSeverity.toString().toUpperCase()}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.fireRed),
                        ),
                      ),
                  ],
                ),
              ),
              // panel rows
              Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (panels.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No AI damage data available.', style: TextStyle(color: (isDark ? AppColors.onSurfaceVariant : Colors.black54))),
                      ),
                    ...panels.map((panel) {
                      final severity = (panel['panel_severity']?.toString() ?? 'ringan').toUpperCase();
                      final cost = panel['calculated_cost'] ?? 0;
                      final hasGores = (panel['scratches_found'] as num? ?? 0) > 0;
                      final hasPenyok = (panel['dents_found'] as num? ?? 0) > 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: (isDark ? AppColors.surfaceContainerLow : Colors.grey.shade50),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    panel['panel_name']?.toString() ?? '-',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Colors.black87)),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    [
                                      if (hasGores) '⚡ Gores',
                                      if (hasPenyok) '🔨 Penyok',
                                      if (!hasGores && !hasPenyok) 'Kerusakan Umum',
                                    ].join('  '),
                                    style: TextStyle(fontSize: 11, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54)),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Rp ${_formatCurrency(cost)}',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Colors.black87)),
                                ),
                                SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.fireRed.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    severity,
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.fireRed),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    // Total cost row
                    if (panels.isNotEmpty) ...[
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ESTIMATED TOTAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54), letterSpacing: 0.8)),
                              Text('Incl. color matching & clear coat', style: TextStyle(fontSize: 10, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54))),
                            ],
                          ),
                          Text(
                            'Rp ${_formatCurrency(totalCost)}',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.fireRed),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),

        // Consent line
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (isDark ? AppColors.surfaceContainerLow : Colors.grey.shade50),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'By confirming, you agree to drop off your vehicle based on the estimated structural damage above. Final price may vary after physical inspection.',
                  style: TextStyle(fontSize: 11, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54), height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewSection({
    required IconData icon,
    required String title,
    required List<_ReviewRow> rows,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceContainerLowest : Colors.white),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.surfaceContainerLow : Colors.grey.shade50),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.fireRed),
                SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Colors.black87))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: rows.map((row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(row.label, style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Colors.black54))),
                    Text(row.value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: (isDark ? AppColors.onSurface : Colors.black87))),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProgressSteps(),
        SizedBox(height: 16),
        if (_currentStep == 0) ...[
          _buildInstructionBanner(),
          SizedBox(height: 16),
          _buildPhotoUpload(),
          SizedBox(height: 16),
          _buildDigitalTwin(),
          SizedBox(height: 16),
          _buildDamageAssessmentReport(),
        ] else if (_currentStep == 1) ...[
          _buildStep2(),
        ] else if (_currentStep == 2) ...[
          _buildStep3(),
        ] else if (_currentStep == 3) ...[
          _buildStep4(),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String ctaTitle = '';
    String ctaSubtitle = '';
    if (_currentStep == 0) {
      if (_aiResult == null) {
        ctaTitle = 'Analyze Damage';
        ctaSubtitle = 'Run AI vision estimation';
      } else {
        ctaTitle = 'Step 2 Demographics';
        ctaSubtitle = 'Continue to Schedule Booking';
      }
    } else if (_currentStep == 1) {
      ctaTitle = 'Step 3 Contact Details';
      ctaSubtitle = 'Continue to Next Step';
    } else if (_currentStep == 2) {
      ctaTitle = 'Step 4 Confirmation';
      ctaSubtitle = 'Continue to Final Review';
    } else {
      ctaTitle = 'Confirm Booking';
      ctaSubtitle = 'Submit for Workshop Allocation';
    }

    return Scaffold(
      backgroundColor: (isDark ? AppColors.surface : Colors.white),
      appBar: const ReVAppBar(
        title: Text('AI Body Repair Estimator'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
            child: _buildContent(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: (isDark ? AppColors.surface : Colors.white),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))
                ],
              ),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: (isDark ? AppColors.surfaceContainerHighest : Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: Icon(Icons.arrow_back),
                          onPressed: () {
                            setState(() => _currentStep -= 1);
                          },
                        ),
                      ),
                    ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isAnalyzing ? null : _onNextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.fireRed,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(ctaTitle.toUpperCase(), style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                              SizedBox(height: 2),
                              _isAnalyzing 
                                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : Text(ctaSubtitle, style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _ReviewRow {
  final String label;
  final String value;
  const _ReviewRow(this.label, this.value);
}
