import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pricing_matrix.dart';

// --- DATA MODELS ---

/// Data model encapsulating the outbound request structure.
class VisionRequestPayload {
  final String jobId;
  final List<String> damageImages;

  VisionRequestPayload({
    required this.jobId,
    required this.damageImages,
  });

  /// Helper validation property ensuring an intake request cannot be dispatched
  /// if 'damage_images' is completely empty.
  bool get isValid => damageImages.isNotEmpty;
}

/// Data model representing a single panel's damage assessment.
class PanelDamageDetail {
  final String panelName;
  final String panelSeverity;
  final int scratchesFound;
  final int dentsFound;
  final bool requiresReplacement;

  PanelDamageDetail({
    required this.panelName,
    required this.panelSeverity,
    required this.scratchesFound,
    required this.dentsFound,
    required this.requiresReplacement,
  });

  factory PanelDamageDetail.fromJson(Map<String, dynamic> json) {
    return PanelDamageDetail(
      panelName: json['panel_name'] ?? 'Unknown',
      panelSeverity: json['panel_severity'] ?? 'ringan',
      scratchesFound: json['scratches_found'] ?? 0,
      dentsFound: json['dents_found'] ?? 0,
      requiresReplacement: json['requires_replacement'] ?? false,
    );
  }
}

/// Data model encapsulating the inbound JSON structure returned by the Vision AI.
class VisionResponsePayload {
  final String engineProcessed;
  final String severityClassification;
  final int totalPanelsDamaged;
  final List<PanelDamageDetail> damagedPanelsDetail;
  final double calculatedBaseCost;
  final int estimatedDaysToRepair;

  VisionResponsePayload({
    required this.engineProcessed,
    required this.severityClassification,
    required this.totalPanelsDamaged,
    required this.damagedPanelsDetail,
    required this.calculatedBaseCost,
    required this.estimatedDaysToRepair,
  });

  factory VisionResponsePayload.fromJson(Map<String, dynamic> json) {
    final meta = json['analysis_metadata'] ?? {};
    final assessment = json['assessment'] ?? {};
    final financial = json['financial_estimation'] ?? {};

    final panelsData = assessment['damaged_panels_detail'] as List<dynamic>? ?? [];
    final panelsList = panelsData.map((e) => PanelDamageDetail.fromJson(e as Map<String, dynamic>)).toList();

    // Deterministic price calculation overriding AI hallucination
    double deterministicCost = 0.0;
    for (final panel in panelsList) {
      deterministicCost += PricingMatrix.calculateCost(panel.panelName, panel.panelSeverity);
    }

    return VisionResponsePayload(
      engineProcessed: meta['engine_processed'] ?? 'unknown',
      severityClassification: assessment['severity_classification'] ?? 'unknown',
      totalPanelsDamaged: assessment['total_panels_damaged'] ?? panelsList.length,
      damagedPanelsDetail: panelsList,
      calculatedBaseCost: deterministicCost,
      estimatedDaysToRepair: financial['estimated_days_to_repair'] ?? 0,
    );
  }
}

// --- ORCHESTRATOR SERVICE ---

/// Unified concrete service class managing Vision AI dispatching,
/// configuration lookups, and defensive fallback logic.
class VisionAiOrchestrator {
  final SupabaseClient _supabase;
  final String _openAiKey;
  final String _geminiKey;

  VisionAiOrchestrator(this._supabase, this._openAiKey, this._geminiKey);

  static const String _promptText = '''
Analyze the car body damage from these images.
Valid panel names are: Bumper Depan, Spoiler Bumper depan, Kap Mesin, Bumper Belakang, Spoiler Bumper Belakang, Bagasi, Spoiler Bagasi, Fender RH, Pintu Depan RH, Spion RH, Pintu Belakang RH, Quarter RH, Trisplang RH, Side Roof RH, Fender LH, Pintu Depan LH, Spion LH, Pintu Belakang LH, Quarter LH, Trisplang LH, Side Roof LH, Roof, Cover.

For each damaged panel found, classify its specific severity into: 'ringan', 'sedang', or 'berat'.
Also classify the overall severity of the car damage.
Return precise counts for dents, scratches, and broken panels in the exact following JSON format:
{
  "analysis_metadata": { "engine_processed": "model-name", "timestamp": "ISO8601" },
  "assessment": {
    "severity_classification": "ringan/sedang/berat",
    "total_panels_damaged": 0,
    "damaged_panels_detail": [
      { "panel_name": "exact_valid_panel_name", "panel_severity": "ringan/sedang/berat", "scratches_found": 0, "dents_found": 0, "requires_replacement": false }
    ]
  },
  "financial_estimation": { "currency": "IDR", "estimated_days_to_repair": 0 }
}
''';

  /// Asynchronous processing method that evaluates the active database engine 
  /// and executes the primary dispatch, falling back dynamically on failure.
  Future<VisionResponsePayload> processDamageIntake(VisionRequestPayload payload) async {
    if (!payload.isValid) {
      throw ArgumentError('Intake request rejected: damage_images payload array is completely empty.');
    }

    // 1. Evaluate and fetch the Primary Engine from 'public.ai_config'
    final primaryConfig = await _fetchEngineConfig(priority: 1);

    try {
      // 2. Dispatch to the Primary Target Endpoint
      return await _dispatchToEngine(primaryConfig, payload);
    } catch (primaryException) {
      // 3. Defensive Error Handling Block (Invalid JSON or API Failure)
      await _logJobFailure(
        payload.jobId, 
        primaryConfig['model_name'], 
        primaryException.toString()
      );

      // 4. Fetch the Secondary Engine (priority_order = 2)
      final secondaryConfig = await _fetchEngineConfig(priority: 2);

      // 5. Seamlessly retry the transaction
      return await _dispatchToEngine(secondaryConfig, payload);
    }
  }

  /// Queries the `ai_config` table for the matching priority engine configuration.
  Future<Map<String, dynamic>> _fetchEngineConfig({required int priority}) async {
    final response = await _supabase
        .from('ai_config')
        .select()
        .eq('is_active', true)
        .eq('priority_order', priority)
        .maybeSingle();

    if (response == null) {
      throw StateError('CRITICAL: No active AI configuration found for priority_order: $priority');
    }
    return response;
  }

  /// Updates job logs in the database when an engine throws an exception.
  Future<void> _logJobFailure(String jobId, String failedModel, String errorDump) async {
    try {
      await _supabase.from('system_logs').insert({
        'job_id': jobId,
        'module': 'VisionAiOrchestrator',
        'model_attempted': failedModel,
        'error_message': errorDump,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Fail silently on log insertion to guarantee the fallback retry circuit executes
    }
  }

  /// Routes the payload to the correct structural parser based on the database provider string.
  Future<VisionResponsePayload> _dispatchToEngine(Map<String, dynamic> config, VisionRequestPayload payload) async {
    final provider = (config['provider'] as String).toLowerCase();
    final modelName = config['model_name'] as String;

    if (provider.contains('openai')) {
      return await _executeOpenAiRequest(modelName, payload);
    } else if (provider.contains('google') || provider.contains('gemini')) {
      return await _executeGeminiRequest(modelName, payload);
    } else {
      throw UnsupportedError('Unsupported Engine Provider registered in DB: $provider');
    }
  }

  /// Handles the OpenAI payload dispatch and standardizes output.
  Future<VisionResponsePayload> _executeOpenAiRequest(String model, VisionRequestPayload payload) async {
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    
    final List<Map<String, dynamic>> contentArray = [
      { 'type': 'text', 'text': _promptText }
    ];

    for (final imageUrl in payload.damageImages) {
      contentArray.add({
        'type': 'image_url',
        'image_url': { 'url': imageUrl }
      });
    }

    final requestBody = {
      'model': model,
      'response_format': { 'type': 'json_object' },
      'messages': [
        {
          'role': 'user',
          'content': contentArray,
        }
      ]
    };

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_openAiKey',
      },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode != 200) {
      throw Exception('OpenAI API Failure Code ${response.statusCode}: ${response.body}');
    }

    try {
      final jsonResponse = jsonDecode(response.body);
      final rawContentString = jsonResponse['choices'][0]['message']['content'];
      final parsedJson = jsonDecode(rawContentString);
      return VisionResponsePayload.fromJson(parsedJson);
    } catch (e) {
      throw FormatException('Invalid JSON string structure returned from OpenAI endpoint: $e');
    }
  }

  /// Handles the Gemini payload dispatch and standardizes output.
  Future<VisionResponsePayload> _executeGeminiRequest(String model, VisionRequestPayload payload) async {
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_geminiKey');
    
    final List<Map<String, dynamic>> partsArray = [
      { 'text': _promptText }
    ];

    for (final imageUrl in payload.damageImages) {
      partsArray.add({
        'fileData': {
          'mimeType': 'image/jpeg',
          'fileUrl': imageUrl
        }
      });
    }

    final requestBody = {
      'contents': [
        { 'parts': partsArray }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json'
      }
    };

    final response = await http.post(
      url,
      headers: { 'Content-Type': 'application/json' },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode != 200) {
      throw Exception('Gemini API Failure Code ${response.statusCode}: ${response.body}');
    }

    try {
      final jsonResponse = jsonDecode(response.body);
      final rawContentString = jsonResponse['candidates'][0]['content']['parts'][0]['text'];
      final parsedJson = jsonDecode(rawContentString);
      return VisionResponsePayload.fromJson(parsedJson);
    } catch (e) {
      throw FormatException('Invalid JSON string structure returned from Gemini endpoint: $e');
    }
  }
}
