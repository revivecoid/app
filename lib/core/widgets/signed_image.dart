// lib/core/widgets/signed_image.dart
//
// Drop-in replacement for Image.network() when the source is a private
// Supabase storage key (not a full URL).
//
// Usage:
//   SignedImage(fileKey: photo.r2FileKey, fit: BoxFit.cover)
//
// The widget calls createSignedUrl once per build lifecycle (TTL 1 hour).
// On error it shows a broken-image placeholder consistent with the rest of
// the app.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignedImage extends StatefulWidget {
  const SignedImage({
    super.key,
    required this.fileKey,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.bucket = 'revive-photos',
    this.ttlSeconds = 3600,
  });

  final String? fileKey;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final String bucket;
  final int ttlSeconds;

  @override
  State<SignedImage> createState() => _SignedImageState();
}

class _SignedImageState extends State<SignedImage> {
  late Future<String?> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = _resolve();
  }

  @override
  void didUpdateWidget(SignedImage old) {
    super.didUpdateWidget(old);
    if (old.fileKey != widget.fileKey) {
      _urlFuture = _resolve();
    }
  }

  Future<String?> _resolve() async {
    final key = widget.fileKey;
    if (key == null || key.isEmpty) return null;
    // Already a full URL (e.g. avatar from Google OAuth) — pass through
    if (key.startsWith('http://') || key.startsWith('https://')) return key;
    try {
      return await Supabase.instance.client.storage
          .from(widget.bucket)
          .createSignedUrl(key, widget.ttlSeconds);
    } catch (e) {
      debugPrint('[SignedImage] createSignedUrl failed for $key: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final broken = widget.errorWidget ??
        Container(
          width: widget.width,
          height: widget.height,
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.broken_image_outlined, color: cs.outline),
        );

    Widget wrap(Widget child) {
      if (widget.borderRadius != null) {
        return ClipRRect(borderRadius: widget.borderRadius!, child: child);
      }
      return child;
    }

    return FutureBuilder<String?>(
      future: _urlFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return wrap(
            widget.placeholder ??
                Container(
                  width: widget.width,
                  height: widget.height,
                  color: cs.surfaceContainerHighest,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
          );
        }
        final url = snap.data;
        if (url == null) return wrap(broken);
        return wrap(
          Image.network(
            url,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            errorBuilder: (_, __, ___) => broken,
          ),
        );
      },
    );
  }
}
