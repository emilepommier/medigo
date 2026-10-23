import 'package:flutter/material.dart';
import 'package:medigo/theme.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:image_background_remover/image_background_remover.dart';
// Note: image_background_remover package integration
// The package API needs verification - current implementation uses a fallback

/// Preview screen for background removal with approve/retry/cancel actions.
class BackgroundRemovalPreview extends StatefulWidget {
  final Uint8List originalBytes;
  const BackgroundRemovalPreview({super.key, required this.originalBytes});

  static Future<Uint8List?> show(BuildContext context, Uint8List originalBytes) async {
    return showModalBottomSheet<Uint8List?>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => BackgroundRemovalPreview(originalBytes: originalBytes),
    );
  }

  @override
  State<BackgroundRemovalPreview> createState() => _BackgroundRemovalPreviewState();
}

class _BackgroundRemovalPreviewState extends State<BackgroundRemovalPreview> {
  bool _processing = true;
  Uint8List? _processedBytes;
  String? _error;
  static bool _ortInitialized = false;
  bool _approving = false; // loading state when user taps Approuver

  @override
  void initState() {
    super.initState();
    _removeBackground();
  }

  Future<void> _ensureOrtInitialized() async {
    if (_ortInitialized || kIsWeb) return; // ONNX not supported on web preview
    try {
      await BackgroundRemover.instance.initializeOrt();
      _ortInitialized = true;
    } catch (e) {
      debugPrint('BackgroundRemover ORT init failed: $e');
      rethrow;
    }
  }

  Future<void> _removeBackground() async {
    setState(() {
      _processing = true;
      _error = null;
      _processedBytes = null;
    });
    try {
      debugPrint('BR: start (web=$kIsWeb)');
      // Web fallback: return original bytes
      if (kIsWeb) {
        final result = widget.originalBytes;
        if (mounted) {
          setState(() {
            _processedBytes = result;
            _processing = false;
          });
        }
        debugPrint('BR: web fallback complete');
        return;
      }

      await _ensureOrtInitialized();
      debugPrint('BR: ORT initialized');

      // Perform background removal with a timeout safeguard
      final ui.Image imgNoBg = await BackgroundRemover.instance
          .removeBg(widget.originalBytes)
          .timeout(const Duration(seconds: 25), onTimeout: () {
        throw TimeoutException('Background removal timed out');
      });
      try {
        final byteData = await imgNoBg.toByteData(format: ui.ImageByteFormat.png);
        final result = byteData?.buffer.asUint8List();
        if (result == null) throw Exception('PNG encoding failed');
        if (mounted) {
          setState(() {
            _processedBytes = result;
            _processing = false;
          });
        }
        debugPrint('BR: success, bytes=${_processedBytes?.length}');
      } finally {
        // ignore: deprecated_member_use
        imgNoBg.dispose();
      }
    } catch (e, st) {
      debugPrint('Background removal failed: $e\n$st');
      if (mounted) {
        setState(() {
          _error = 'Échec de la suppression de l\'arrière-plan';
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.9,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.auto_fix_high, color: cs.primary),
                const SizedBox(width: 8),
                Text('Suppression de l\'arrière-plan', style: t.titleLarge),
                if (kIsWeb) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Aperçu web: le traitement réel fonctionne sur iOS/Android',
                    child: Icon(Icons.info_outline, color: cs.onSurfaceVariant.withValues(alpha: 0.7), size: 18),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Preview area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _processing
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text('Traitement en cours...', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 48, color: cs.error),
                              const SizedBox(height: 16),
                              Text(_error!, style: t.bodyLarge?.copyWith(color: cs.error)),
                            ],
                          ),
                        )
                      : Card(
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Checkerboard background to visualize transparency without requiring an asset
                              TransparencyGrid(
                                light: cs.surface,
                                dark: cs.surfaceContainerHighest,
                              ),
                              Center(
                                child: _processedBytes != null
                                    ? Image.memory(_processedBytes!, fit: BoxFit.contain)
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
            ),
          ),
          // Actions
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_processedBytes != null) ...[
                    FilledButton.icon(
                      onPressed: (_processing || _approving)
                          ? null
                          : () {
                              setState(() => _approving = true);
                              try {
                                Navigator.of(context).pop(_processedBytes);
                              } catch (e) {
                                debugPrint('Approve pop failed: $e');
                                if (mounted) setState(() => _approving = false);
                              }
                            },
                      icon: _approving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: Text(_approving ? 'Validation…' : 'Approuver'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      if (_error != null || _processedBytes != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _processing ? null : _removeBackground,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Réessayer'),
                          ),
                        ),
                      if (_error != null || _processedBytes != null) const SizedBox(width: 8),
                      if (_error != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _processing ? null : () => Navigator.of(context).pop(widget.originalBytes),
                            icon: const Icon(Icons.image_outlined),
                            label: const Text("Utiliser l'image originale"),
                          ),
                        ),
                      if (_error != null) const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _processing ? null : () => Navigator.of(context).pop(null),
                          icon: const Icon(Icons.close),
                          label: const Text('Annuler'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple checkerboard painter to visualize transparency without bundling an image asset.
class TransparencyGrid extends StatelessWidget {
  final Color light;
  final Color dark;
  final double cellSize;
  const TransparencyGrid({super.key, required this.light, required this.dark, this.cellSize = 12});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TransparencyGridPainter(light: light, dark: dark, cell: cellSize),
    );
  }
}

class _TransparencyGridPainter extends CustomPainter {
  final Color light;
  final Color dark;
  final double cell;
  _TransparencyGridPainter({required this.light, required this.dark, required this.cell});

  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = light;
    final darkPaint = Paint()..color = dark;
    // Fill background first
    canvas.drawRect(Offset.zero & size, lightPaint);
    // Draw alternating squares
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final isDark = ((x / cell).floor() + (y / cell).floor()) % 2 == 0;
        if (isDark) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), darkPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TransparencyGridPainter oldDelegate) =>
      oldDelegate.light != light || oldDelegate.dark != dark || oldDelegate.cell != cell;
}
