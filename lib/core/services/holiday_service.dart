import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class HolidayService {
  static Future<Map<DateTime, String>> fetchIndonesianHolidays(int year) async {
    try {
      final response = await http.get(Uri.parse('https://api-harilibur.vercel.app/api?year=$year'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final Map<DateTime, String> holidays = {};
        for (var item in data) {
          if (item['is_national_holiday'] == true) {
            final dateStr = item['holiday_date'];
            if (dateStr != null) {
               holidays[DateTime.parse(dateStr)] = item['holiday_name'] ?? 'Holiday';
            }
          }
        }
        return holidays;
      }
    } catch (e) {
      debugPrint('Error fetching holidays: $e');
    }
    return {};
  }
}
