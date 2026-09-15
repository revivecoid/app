import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/image_compressor.dart';
import '../providers/panel_selection_provider.dart';

import '../../../../core/theme/app_theme.dart';

class EstimatorScreen extends ConsumerStatefulWidget {
  const EstimatorScreen({super.key});

  @override
  ConsumerState<EstimatorScreen> createState() => _EstimatorScreenState();
}

class _EstimatorScreenState extends ConsumerState<EstimatorScreen> {
  int _currentStep = 0;
  final _formKey = GlobalKey<FormState>();
  
  // Step 1: Contact
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  // Step 2: Demographics
  // ignore: unused_field
  String? _selectedMake;
  // ignore: unused_field
  String? _selectedModel;
  final TextEditingController _yearController = TextEditingController();

  // Step 3: Visual Intake
  XFile? _selectedImage;
  bool _isAnalyzing = false;
  String? _aiResult;
  Map<String, dynamic>? _structuredData;

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
      // 1. Client-side compression enforcing <300KB
      final compressedBytes = await ImageCompressor.compressImage(_selectedImage!);
      
      // 2. Upload to Cloudflare R2 (Simulated via Supabase Storage interface for now)
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Supabase.instance.client.storage
          .from('revive-photos')
          .uploadBinary(fileName, compressedBytes);
          
      // 3. Trigger Supabase Edge Function to hit AI models (Gemini/Groq Fallback)
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

  Widget _buildPanelGroup(List<CarPanel> panels) {
    final selected = ref.watch(selectedPanelsProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: panels.map((p) {
          final isSelected = selected.contains(p);
          return FilterChip(
            label: Text(p.label, style: TextStyle(color: isSelected ? Colors.white : null)),
            selected: isSelected,
            selectedColor: const Color(0xFF2563EB),
            checkmarkColor: Colors.white,
            onSelected: (_) => ref.read(selectedPanelsProvider.notifier).togglePanel(p),
          );
        }).toList(),
      ),
    );
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

  Widget _buildEstimationResult() {
    if (_structuredData == null || _structuredData!['assessment'] == null) {
      // Fallback if parsing failed
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.grey[900],
        child: Text('AI Assessment:\n$_aiResult', style: const TextStyle(color: Colors.white)),
      );
    }

    final panels = _structuredData!['assessment']['damaged_panels_detail'] as List<dynamic>? ?? [];
    final totalCost = _structuredData!['financial_estimation']?['calculated_base_cost'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Damage Assessment Report',
            style: TextStyle(color: AppColors.fireRed, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              dataRowMinHeight: 60,
              dataRowMaxHeight: 75,
              headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              dataTextStyle: const TextStyle(color: Colors.white70),
              dividerThickness: 0.5,
              columns: const [
                DataColumn(label: Text('No.')),
                DataColumn(label: Text('Panel & Observasi')),
                DataColumn(label: Text('Tingkat Kerusakan')),
                DataColumn(label: Text('Perkiraan Biaya')),
              ],
              rows: List<DataRow>.generate(panels.length, (index) {
                final panel = panels[index];
                
                // Extract damage indicators safely
                final scratches = (panel['scratches_found'] as num?) ?? 0;
                final dents = (panel['dents_found'] as num?) ?? 0;
                final severity = (panel['panel_severity']?.toString() ?? 'ringan').toLowerCase();
                
                // Determine badge colors
                Color badgeBgColor = Colors.green.withValues(alpha: 0.2);
                Color badgeTextColor = Colors.greenAccent;
                if (severity == 'berat') {
                  badgeBgColor = Colors.red.withValues(alpha: 0.2);
                  badgeTextColor = Colors.redAccent;
                } else if (severity == 'sedang') {
                  badgeBgColor = Colors.orange.withValues(alpha: 0.2);
                  badgeTextColor = Colors.orangeAccent;
                }

                return DataRow(
                  cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(panel['panel_name']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            if (scratches > 0 || dents > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (scratches > 0) const Text('⚡ Goresan ', style: TextStyle(fontSize: 12, color: Colors.orange)),
                                  if (dents > 0) const Text('🔨 Penyok', style: TextStyle(fontSize: 12, color: Colors.blueAccent)),
                                ],
                              ),
                            ]
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeBgColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: badgeTextColor),
                        ),
                        child: Text(
                          severity.toUpperCase(),
                          style: TextStyle(color: badgeTextColor, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    DataCell(Text('Rp ${_formatCurrency(panel['calculated_cost'] ?? 0)}')),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.grey),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOTAL ESTIMATION:',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                'Rp ${_formatCurrency(totalCost)}',
                style: const TextStyle(color: AppColors.fireRed, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Body Repair Estimator'),
        actions: [
          IconButton(
            icon: Icon(themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              ref.read(themeModeProvider.notifier).state = 
                  themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
            },
          )
        ],
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 2) {
            setState(() => _currentStep += 1);
          } else {
            _submitToVisionAi();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep -= 1);
          }
        },
        steps: [
          Step(
            title: const Text('Contact Details'),
            content: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Full Name'),
                  ),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'WhatsApp Number'),
                    keyboardType: TextInputType.phone,
                  ),
                ],
              ),
            ),
            isActive: _currentStep >= 0,
          ),
          Step(
            title: const Text('Vehicle Demographics'),
            content: Column(
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Car Brand'),
                  items: ['Toyota', 'Honda', 'Mitsubishi'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (val) => setState(() => _selectedMake = val),
                ),
                TextFormField(
                  controller: _yearController,
                  decoration: const InputDecoration(labelText: 'Year of Production'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            isActive: _currentStep >= 1,
          ),
          Step(
            title: const Text('Visual Intake Damage Zone'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Provide a photo of the damage and select the affected panels.'),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _captureImage,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Capture Damage Photo'),
                ),
                if (_selectedImage != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Image Selected: ${_selectedImage!.name}', style: const TextStyle(color: Colors.green)),
                  ),
                
                const SizedBox(height: 24),
                const Text('Select Damaged Panels:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                
                DefaultTabController(
                  length: 5,
                  child: Column(
                    children: [
                      const TabBar(
                        isScrollable: true,
                        labelColor: Color(0xFF2563EB),
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: Color(0xFF2563EB),
                        tabs: [
                          Tab(text: 'Front'),
                          Tab(text: 'Rear'),
                          Tab(text: 'Right Side'),
                          Tab(text: 'Left Side'),
                          Tab(text: 'Roof/Misc'),
                        ],
                      ),
                      SizedBox(
                        height: 200,
                        child: TabBarView(
                          children: [
                            _buildPanelGroup([CarPanel.bumperDepan, CarPanel.spoilerBumperDepan, CarPanel.kapMesin]),
                            _buildPanelGroup([CarPanel.bumperBelakang, CarPanel.spoilerBumperBelakang, CarPanel.bagasi, CarPanel.spoilerBagasi]),
                            _buildPanelGroup([CarPanel.fenderRH, CarPanel.pintuDepanRH, CarPanel.spionRH, CarPanel.pintuBelakangRH, CarPanel.quarterRH, CarPanel.trisplangRH, CarPanel.sideRoofRH]),
                            _buildPanelGroup([CarPanel.fenderLH, CarPanel.pintuDepanLH, CarPanel.spionLH, CarPanel.pintuBelakangLH, CarPanel.quarterLH, CarPanel.trisplangLH, CarPanel.sideRoofLH]),
                            _buildPanelGroup([CarPanel.roof, CarPanel.cover]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isAnalyzing)
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_aiResult != null)
                  _buildEstimationResult(),
              ],
            ),
            isActive: _currentStep >= 2,
          ),
        ],
      ),
    );
  }
}

