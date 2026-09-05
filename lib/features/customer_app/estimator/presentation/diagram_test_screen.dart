import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/rev_app_bar.dart';
import 'widgets/interactive_car_diagram.dart';
import '../providers/panel_selection_provider.dart';

class DiagramTestScreen extends StatefulWidget {
  const DiagramTestScreen({super.key});

  @override
  State<DiagramTestScreen> createState() => _DiagramTestScreenState();
}

class _DiagramTestScreenState extends State<DiagramTestScreen> {
  final Set<CarPanel> _selectedPanels = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ReVAppBar(
        title: const Text('Car Diagram Test Component'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Interactive Car Diagram Widget Sandbox',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: InteractiveCarDiagram(
                      selectedPanels: _selectedPanels,
                      onToggle: (panel) {
                        setState(() {
                          if (_selectedPanels.contains(panel)) {
                            _selectedPanels.remove(panel);
                          } else {
                            _selectedPanels.add(panel);
                          }
                        });
                        debugPrint('Toggled: ${panel.name}');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Toggled panel: ${panel.name}'),
                            duration: const Duration(milliseconds: 500),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
