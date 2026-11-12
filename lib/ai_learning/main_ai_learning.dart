// Entry point for the AI Learning respondent app.
// Build separately from the customer app, e.g.:
//   flutter run -t lib/ai_learning/main_ai_learning.dart
//   flutter build web -t lib/ai_learning/main_ai_learning.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_learning_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  runApp(const AiLearningApp());
}
