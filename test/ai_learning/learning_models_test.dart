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

  // The edge function used to echo whatever the model returned. When the model
  // wrapped its answer in an array, the app crashed with
  // "List<dynamic> is not a subtype of Map<String, dynamic>?". The screen now
  // coerces a list to a map; these lock in that the parser copes either way.
  group('structured data shape tolerance', () {
    test('a list payload still yields panels via its first map', () {
      final raw = <dynamic>[
        {
          'assessment': {
            'damaged_panels_detail': [
              {'panel': 'Bumper Depan', 'panel_severity': 'berat'},
            ],
          },
        },
      ];
      final Map<String, dynamic>? structured = switch (raw) {
        final Map<String, dynamic> m => m,
        final Map m => Map<String, dynamic>.from(m),
        final List l => l.whereType<Map>().isEmpty
            ? null
            : Map<String, dynamic>.from(l.whereType<Map>().first),
        _ => null,
      };
      expect(parseDamagedPanels(structured).single.name, 'Bumper Depan');
    });

    test('an unexpected scalar yields no panels instead of throwing', () {
      const raw = 'model said no damage';
      final Map<String, dynamic>? structured = switch (raw) {
        final Map<String, dynamic> m => m,
        final Map m => Map<String, dynamic>.from(m),
        final List l => l.whereType<Map>().isEmpty
            ? null
            : Map<String, dynamic>.from(l.whereType<Map>().first),
        _ => null,
      };
      expect(parseDamagedPanels(structured), isEmpty);
    });
  });
}
