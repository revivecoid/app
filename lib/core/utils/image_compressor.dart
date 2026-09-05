import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';

class ImageCompressor {
  /// Compresses a local image file down to web-optimized constraints (<300KB Target).
  /// [fileToCompress] represents the raw image picked from the device camera or gallery.
  /// 
  /// STRICT ARCHITECTURE GUARD: This method utilizes dart:io [File] structures and the path_provider 
  /// filesystem. It is exclusively for native Android/iOS execution parameters. For cross-platform 
  /// memory buffering including Web compilation, use [compressImage] instead.
  static Future<File?> compressCarDamagePhoto(File fileToCompress) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Platform Safety Constraint Guard
      if (kIsWeb) {
        debugPrint('❌ ImageCompressor Error: dart:io File filesystem operations are strictly unsupported on Web compilation targets.');
        return null;
      }

      // 1. Validate file existence before processing transactions
      if (!await fileToCompress.exists()) {
        debugPrint('❌ ImageCompressor Error: Target file does not exist on filesystem.');
        return null;
      }

      // 2. Fetch the device's temporary directory to output our compressed file path layer safely
      final tempDir = await getTemporaryDirectory();
      
      // Generate a unique filename prefix using epoch timestamp to avoid file locking collisions
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String targetPath = p.join(
        tempDir.path, 
        'reV_compressed_${timestamp}.jpg' // Enforcing .jpg target format for compression subsystem recognition
      );

      debugPrint('⚡ Initiating native compression pipeline for: ${p.basename(fileToCompress.path)}');
      final originalSize = await fileToCompress.length();
      debugPrint('📊 Original file size: ${(originalSize / 1024).toStringAsFixed(2)} KB');

      // 3. Execute the image compression framework (Tier 1 Constraint)
      // Resizes canvas to max 1920x1080 and compresses parameters down to 70% quality
      final XFile? compressedXFile = await FlutterImageCompress.compressAndGetFile(
        fileToCompress.absolute.path,
        targetPath,
        quality: 70,
        minWidth: 1920,
        minHeight: 1080,
        format: CompressFormat.jpeg,
      );

      if (compressedXFile == null) {
        debugPrint('❌ ImageCompressor Error: The compression subsystem returned a null reference pointer.');
        return null;
      }

      File compressedFile = File(compressedXFile.path);
      int finalLength = await compressedFile.length();
      
      debugPrint('✅ Tier 1 Compression transaction successful.');
      debugPrint('📉 Compressed file size: ${(finalLength / 1024).toStringAsFixed(2)} KB');

      // 4. Assert size threshold constraints (< 300KB Guard)
      if (finalLength > 300 * 1024) {
        debugPrint('⚠️ Warning: Compressed output size exceeds 300KB threshold. Executing secondary fallback reduction parameter loop...');
        
        // Secondary ultra-compression fallback loop targeting complex geometry arrays (Tier 2 Constraint)
        final XFile? heavyCompressedXFile = await FlutterImageCompress.compressAndGetFile(
          fileToCompress.absolute.path, // Compressing from the absolute origin preserves structural integrity over double-compressing artifacts
          p.join(tempDir.path, 'reV_fallback_${timestamp}.jpg'),
          quality: 50,
          minWidth: 1280,
          minHeight: 720,
          format: CompressFormat.jpeg,
        );
        
        if (heavyCompressedXFile != null) {
          compressedFile = File(heavyCompressedXFile.path);
          finalLength = await compressedFile.length();
          debugPrint('🎯 Tier 2 Fallback compress complete: ${(finalLength / 1024).toStringAsFixed(2)} KB');
        } else {
          debugPrint('❌ ImageCompressor Error: Tier 2 fallback loop aborted. Reverting to Tier 1 output.');
        }
      }

      stopwatch.stop();
      debugPrint('⏱️ File System Compression pipeline execution duration: ${stopwatch.elapsedMilliseconds}ms');

      return compressedFile;
    } catch (e, stackTrace) {
      debugPrint('❌ ImageCompressor Severe Failure Exception: $e');
      debugPrint('🗒️ Exception StackTrace: $stackTrace');
      return null;
    }
  }

  /// Universal Memory-Buffered Compression Pipeline.
  /// Operates safely across Android, iOS, and Web compilations without requiring physical filesystem paths.
  /// Generates a standard [Uint8List] payload optimized strictly for seamless Cloudflare R2 HTTP streaming.
  static Future<Uint8List> compressImage(XFile rawImage) async {
    final stopwatch = Stopwatch()..start();
    debugPrint('⚡ Initiating Universal Memory Compression pipeline for: ${rawImage.name}');
    
    try {
      final Uint8List originalBytes = await rawImage.readAsBytes();
      final int originalLength = originalBytes.length;
      debugPrint('📊 Original payload buffer size: ${(originalLength / 1024).toStringAsFixed(2)} KB');

      // Tier 1 Constraint: 1080p @ 70% Quality
      Uint8List compressedBytes = await FlutterImageCompress.compressWithList(
        originalBytes,
        minHeight: 1080,
        minWidth: 1920,
        quality: 70,
        format: CompressFormat.jpeg,
      );

      debugPrint('✅ Tier 1 Compression transaction complete.');
      debugPrint('📉 Tier 1 payload buffer size: ${(compressedBytes.length / 1024).toStringAsFixed(2)} KB');

      // Tier 2 Failsafe Guard: 720p @ 50% Quality constraint if payload > 300KB
      if (compressedBytes.length > 300 * 1024) {
        debugPrint('⚠️ Warning: Payload buffer exceeds 300KB constraint. Executing Tier 2 reduction engine...');
        
        compressedBytes = await FlutterImageCompress.compressWithList(
          originalBytes, 
          minHeight: 720,
          minWidth: 1280,
          quality: 50,
          format: CompressFormat.jpeg,
        );
        debugPrint('🎯 Tier 2 Fallback Engine complete: ${(compressedBytes.length / 1024).toStringAsFixed(2)} KB');
      }

      stopwatch.stop();
      debugPrint('⏱️ Universal Memory Compression pipeline execution duration: ${stopwatch.elapsedMilliseconds}ms');
      
      return compressedBytes;
    } catch (e, stackTrace) {
      debugPrint('❌ Universal Compressor Severe Failure Exception: $e');
      debugPrint('🗒️ Exception StackTrace: $stackTrace');
      throw Exception('Core image compression engine runtime failure.');
    }
  }
}
