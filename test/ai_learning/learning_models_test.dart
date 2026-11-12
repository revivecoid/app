import 'package:flutter_test/flutter_test.dart';
import 'package:re_v/ai_learning/data/learning_models.dart';
import 'package:re_v/ai_learning/data/learning_repository.dart';

void main() {
  group('parseDamagedPanels', () {
    test('returns empty for null or missing assessment', () {
      expect(parseDamagedPanels(null), isEmpty);
      expect(parseDamagedPanels({}), isEmpty);
    });

    test('reads panels from assessment and dedupes panels and parts', () {
      final data = {
        'assessment': {
          'damaged_panels_detail': [
            {
              'panel_name': 'Front bumper',
              'panel_severity': 'sedang',
              'spare_parts_needed': [
                {'name': 'Bracket', 'quantity': 1, 'reason': 'cracked'},
                {'name': 'Bracket', 'quantity': 2, 'reason': 'dup'},
                {'name': '', 'quantity': 1},
              ],
            },
            {'panel_name': 'Front bumper', 'panel_severity': 'berat'},
            {'panel_name': 'Hood', 'panel_severity': 'ringan'},
          ],
        },
      };

      final panels = parseDamagedPanels(data);

      expect(panels.map((p) => p.name), ['Front bumper', 'Hood']);
      expect(panels.first.severity, 'sedang');
      expect(panels.first.parts.map((p) => p.name), ['Bracket']);
      expect(panels.first.parts.first.quantity, 1);
      expect(panels[1].parts, isEmpty);
    });

    test('falls back to root damaged_panels_detail when no assessment wrapper', () {
      final panels = parseDamagedPanels({
        'damaged_panels_detail': [
          {'panel': 'Door LH', 'panel_severity': 'ringan'},
        ],
      });
      expect(panels.single.name, 'Door LH');
    });
  });

  test('partKey is stable per panel and part', () {
    expect(partKey('Hood', 'Hinge'), 'Hood::Hinge');
  });
}
