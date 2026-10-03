// lib/core/services/cms_l10n_service.dart
//
// CMS-backed dual-language string resolution.
//
// Usage in any ConsumerWidget / ConsumerState:
//
//   final cms = ref.watch(cmsL10nProvider);
//   Text(cms.t('about_title', en: 'About Revive', id: 'Tentang Revive'))
//
// Keys with `_id` suffix in cms_settings override the Indonesian value.
// Keys with `_en` suffix override the English value.
// Bare key (no suffix) is the English fallback when no `_en` key exists.
//
// Admin can edit both sides via the Language Strings tab in Admin Central →
// Frontend Content Studio.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class CmsL10n {
  final Map<String, String> _s;
  final bool isId;

  const CmsL10n(this._s, {required this.isId});

  /// Resolve a dual-language string.
  ///
  /// Priority (Indonesian locale):
  ///   1. cms_settings key `${k}_id`
  ///   2. cms_settings key `${k}` (bare — legacy / EN-only entries fall through)
  ///   3. Dart fallback [id]
  ///
  /// Priority (English locale):
  ///   1. cms_settings key `${k}_en`
  ///   2. cms_settings key `${k}` (bare)
  ///   3. Dart fallback [en]
  String t(String k, {required String en, required String id}) {
    if (isId) {
      final v = _s['${k}_id'];
      if (v != null && v.isNotEmpty) return v;
      final bare = _s[k];
      if (bare != null && bare.isNotEmpty) return bare;
      return id;
    } else {
      final v = _s['${k}_en'];
      if (v != null && v.isNotEmpty) return v;
      final bare = _s[k];
      if (bare != null && bare.isNotEmpty) return bare;
      return en;
    }
  }

  /// All raw cms_settings map (for admin editor).
  Map<String, String> get raw => Map.unmodifiable(_s);

  /// List all language-related keys (those ending _en or _id, or in a lang group).
  Map<String, Map<String, String>> get langKeys {
    final result = <String, Map<String, String>>{};
    for (final entry in _s.entries) {
      final k = entry.key;
      String? base;
      String? lang;
      if (k.endsWith('_id')) {
        base = k.substring(0, k.length - 3);
        lang = 'id';
      } else if (k.endsWith('_en')) {
        base = k.substring(0, k.length - 3);
        lang = 'en';
      } else {
        // bare key — treat as EN default
        base = k;
        lang = 'en';
      }
      result.putIfAbsent(base, () => {});
      result[base]![lang] = entry.value;
    }
    return result;
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class CmsL10nNotifier extends AsyncNotifier<CmsL10n> {
  @override
  Future<CmsL10n> build() => _fetch(isId: false);

  Future<CmsL10n> _fetch({required bool isId}) async {
    try {
      final res = await Supabase.instance.client.rpc('get_cms_settings');
      final map = (res is Map)
          ? res.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
          : <String, String>{};
      return CmsL10n(map, isId: isId);
    } catch (e) {
      debugPrint('[CmsL10n] load error: $e');
      return CmsL10n({}, isId: isId);
    }
  }

  Future<void> reload({required bool isId}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(isId: isId));
  }

  Future<void> setSetting(String key, String value, String cat) async {
    await Supabase.instance.client.rpc('set_cms_setting',
        params: {'p_key': key, 'p_value': value, 'p_category': cat});
    // Optimistically update local state
    final prev = state.valueOrNull;
    if (prev != null) {
      final newMap = Map<String, String>.from(prev.raw);
      newMap[key] = value;
      state = AsyncData(CmsL10n(newMap, isId: prev.isId));
    }
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final cmsL10nProvider =
    AsyncNotifierProvider<CmsL10nNotifier, CmsL10n>(CmsL10nNotifier.new);

/// Convenience: synchronous access with empty fallback (never null).
/// Use inside widgets that watch cmsL10nProvider.
extension CmsL10nRef on AsyncValue<CmsL10n> {
  CmsL10n get orEmpty => when(
        data: (d) => d,
        loading: () => const CmsL10n({}, isId: false),
        error: (_, __) => const CmsL10n({}, isId: false),
      );
}
