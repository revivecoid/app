import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Cached pricing rule entry ──────────────────────────────────────────────────
class _PricingRule {
  final double basePrice;
  final double sedangMultiplier;
  final double beratMultiplier;

  const _PricingRule({
    required this.basePrice,
    this.sedangMultiplier = 1.5,
    this.beratMultiplier = 2.0,
  });
}

// ── PricingMatrix ─────────────────────────────────────────────────────────────
//
// Fetches pricing rules from the `pricing_rules` Supabase table on first call
// and caches them for the lifetime of the app session.
// Falls back to hardcoded defaults if the DB is unreachable or the table is empty.
//
class PricingMatrix {
  PricingMatrix._();

  // ── In-process cache (null = not yet loaded) ──
  static Map<String, _PricingRule>? _cache;

  // ── Hardcoded fallback — matches the CMS default values ──
  static const Map<String, double> _fallbackBasePrices = {
    'Bumper Depan': 500500,
    'Spoiler Bumper depan': 286000,
    'Kap Mesin': 715000,
    'Bumper Belakang': 500500,
    'Spoiler Bumper Belakang': 286000,
    'Bagasi': 643500,
    'Spoiler Bagasi': 286000,
    'Fender RH': 572000,
    'Pintu Depan RH': 572000,
    'Spion RH': 143000,
    'Pintu Belakang RH': 572000,
    'Quarter RH': 572000,
    'Trisplang RH': 357500,
    'Side Roof RH': 357500,
    'Fender LH': 572000,
    'Pintu Depan LH': 572000,
    'Spion LH': 143000,
    'Pintu Belakang LH': 572000,
    'Quarter LH': 572000,
    'Trisplang LH': 357500,
    'Side Roof LH': 357500,
    'Roof': 1001000,
    'Cover': 286000,
  };

  static const List<String> validPanelNames = [
    'Bumper Depan', 'Spoiler Bumper depan', 'Kap Mesin', 'Bumper Belakang',
    'Spoiler Bumper Belakang', 'Bagasi', 'Spoiler Bagasi', 'Fender RH',
    'Pintu Depan RH', 'Spion RH', 'Pintu Belakang RH', 'Quarter RH',
    'Trisplang RH', 'Side Roof RH', 'Fender LH', 'Pintu Depan LH',
    'Spion LH', 'Pintu Belakang LH', 'Quarter LH', 'Trisplang LH',
    'Side Roof LH', 'Roof', 'Cover'
  ];

  // ── Load (or return cached) rules from Supabase ───────────────────────────
  static Future<Map<String, _PricingRule>> _loadRules() async {
    if (_cache != null) return _cache!;

    try {
      final rows = await Supabase.instance.client
          .from('pricing_rules')
          .select('panel_name, base_rate, severity_min, severity_max');

      if (rows.isEmpty) {
        _cache = _buildFallbackCache();
        return _cache!;
      }

      _cache = {
        for (final r in (rows as List))
          r['panel_name'] as String: _PricingRule(
            basePrice: (r['base_rate'] as num).toDouble(),
            sedangMultiplier: (r['severity_min'] as num?)?.toDouble() ?? 1.5,
            beratMultiplier: (r['severity_max'] as num?)?.toDouble() ?? 2.0,
          )
      };
    } catch (e) {
      // DB unreachable — use hardcoded fallback silently
      debugPrint('[PricingMatrix] DB fetch failed, using fallback: $e');
      _cache = _buildFallbackCache();
    }

    return _cache!;
  }

  static Map<String, _PricingRule> _buildFallbackCache() => {
    for (final entry in _fallbackBasePrices.entries)
      entry.key: _PricingRule(basePrice: entry.value)
  };

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Calculates the cost for a single panel + severity combination.
  /// Uses live DB rules; falls back to hardcoded defaults if DB is unavailable.
  static Future<double> calculateCost(String panelName, String severity) async {
    final rules = await _loadRules();
    final rule = rules[panelName];

    final basePrice = rule?.basePrice ??
        _fallbackBasePrices[panelName] ??
        500000.0;

    final normalizedSeverity = severity.toLowerCase();
    double multiplier = 1.0;
    if (normalizedSeverity == 'sedang') {
      multiplier = rule?.sedangMultiplier ?? 1.5;
    } else if (normalizedSeverity == 'berat') {
      multiplier = rule?.beratMultiplier ?? 2.0;
    }

    return basePrice * multiplier;
  }

  /// Call this to pre-warm the cache (e.g. at app startup), so the
  /// first estimation request has zero latency from DB lookup.
  static Future<void> preload() async => _loadRules();

  /// Invalidates the cache so the next call fetches fresh rules from DB.
  /// Call this after the admin saves changes in the Pricing Rules CMS screen.
  static void invalidateCache() => _cache = null;
}

