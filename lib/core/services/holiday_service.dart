// lib/core/services/holiday_service.dart
//
// REL-16 fix: single source — reads public.holidays table, not external API
// REL-14 fix: timeout, fail-open (returns empty on error, cached on success)
// C-41 fix: client no longer calls third-party API

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HolidayService {
  static Map<DateTime, String>? _cache;
  static DateTime? _cacheDate;

  /// Returns holidays for [year] from the public.holidays DB table.
  /// Falls back to last cached value on error (fail-open).
  static Future<Map<DateTime, String>> fetchIndonesianHolidays(int year) async {
    // Return cache if fetched today
    if (_cache != null && _cacheDate != null &&
        _cacheDate!.year == DateTime.now().year &&
        _cacheDate!.month == DateTime.now().month &&
        _cacheDate!.day == DateTime.now().day) {
      return Map.from(_cache!);
    }

    try {
      final nextYear = year + 1;
      final response = await Supabase.instance.client
          .from('holidays')
          .select('date, name')
          .gte('date', '$year-01-01')
          .lte('date', '$nextYear-12-31')
          .timeout(const Duration(seconds: 10));

      final Map<DateTime, String> result = {};
      for (final row in response as List) {
        final dateStr = row['date']?.toString();
        final name = row['name']?.toString() ?? 'Hari Libur';
        if (dateStr != null) {
          try {
            result[DateTime.parse(dateStr)] = name;
          } catch (_) {}
        }
      }

      _cache = result;
      _cacheDate = DateTime.now();
      return Map.from(result);
    } catch (e) {
      debugPrint('[HolidayService] DB fetch failed: $e — returning cached or empty');
      return _cache != null ? Map.from(_cache!) : {};
    }
  }

  /// Check if a date is a holiday (DB lookup, uses cache).
  static Future<bool> isHoliday(DateTime date) async {
    final holidays = await fetchIndonesianHolidays(date.year);
    final key = DateTime(date.year, date.month, date.day);
    return holidays.containsKey(key);
  }

  /// Clear cache (call on app resume to pick up newly synced holidays).
  static void clearCache() {
    _cache = null;
    _cacheDate = null;
  }
}
