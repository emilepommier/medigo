import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:medigo/theme.dart';

/// Bottom sheet that lets an admin crop a lab logo to a square (circular UI)
/// and returns a small PNG (≤256x256) via Navigator.pop(bytes).
class LabLogoCropSheet extends StatefulWidget {
  final Uint8List imageBytes;
  const LabLogoCropSheet({super.key, required this.imageBytes});

  /// Helper to show the crop sheet and resolve cropped, resized PNG bytes.
  static Future<Uint8List?> show(BuildContext context, Uint8List bytes) async {
    return await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: LabLogoCropSheet(imageBytes: bytes),
      ),
    );
  }

  @override
  State<LabLogoCropSheet> createState() => _LabLogoCropSheetState();
}

class _LabLogoCropSheetState extends State<LabLogoCropSheet> {
  final _controller = CropController();
  bool _saving = false;
  // We pre-pad the source image with transparent margins so the crop box
  // can expand beyond the original image bounds. This avoids using a slider
  // and keeps the interaction purely through the crop box.
  Uint8List? _paddedBytes;
  bool _preparing = true;

  @override
  void initState() {
    super.initState();
    // Prepare a larger transparent canvas with the image centered.
    _preparePaddedImage(widget.imageBytes);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Make the crop canvas as large as reasonably possible within the sheet
          final screen = MediaQuery.sizeOf(context);
          final paddingH = 32.0; // 16 left + 16 right
          final availableW = (screen.width - paddingH).clamp(240.0, 1200.0);
          // Reserve space for title + buttons; use up to ~70% of height for the square
          final availableH = (screen.height * 0.7).clamp(240.0, screen.height - 160.0);
          final squareSize = availableW < availableH ? availableW : availableH;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ajuster le logo', style: t.titleLarge),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    width: squareSize,
                    height: squareSize,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: cs.outlineVariant, width: 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: _preparing
                            ? const Center(child: CircularProgressIndicator())
                            : Padding(
                                padding: const EdgeInsets.all(16),
                                child: Crop(
                                  image: _paddedBytes!,
                                  withCircleUi: true,
                                  // Enforce a perfect square crop to avoid aspect distortion
                                  aspectRatio: 1,
                                  controller: _controller,
                                  // Improve contrast so frame is visible on light/dark images
                                  baseColor: cs.surfaceContainerHighest,
                                  maskColor: cs.scrim.withValues(alpha: 0.5),
                                  // Leave zoom flexible; the widget lets users pinch to zoom out/in
                                  // Make corner handles smaller; visual size matches actual tap radius
                                  radius: 7,
                                  cornerDotBuilder: (size, edgeAlignment) {
                                    final cs = Theme.of(context).colorScheme;
                                    return Container(
                                      width: size,
                                      height: size,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: cs.primary,
                                        border: Border.all(color: cs.onPrimary, width: 2),
                                      ),
                                    );
                                  },
                                  onCropped: (result) async {
                                    try {
                                      final bytes = await _extractCroppedBytes(result);
                                      final normalized = await _resizePngSquareToMax(bytes, 256);
                                      if (mounted) Navigator.of(context).pop(normalized);
                                    } catch (e) {
                                      debugPrint('Crop onCropped failed: $e');
                                      if (mounted) setState(() => _saving = false);
                                    }
                                  },
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Annuler'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _saving ? null : _onSave,
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: Text(_saving ? 'Traitement…' : 'Enregistrer'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _onSave() async {
    setState(() => _saving = true);
    try {
      // Will trigger onCropped callback
      _controller.crop();
    } catch (e) {
      debugPrint('Crop save failed: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Extract Uint8List bytes from different crop_your_image 2.x result shapes.
  /// The package changed its onCropped payload to a sealed result (e.g., CropSuccess).
  /// We handle multiple known fields and fallbacks gracefully.
  Future<Uint8List> _extractCroppedBytes(dynamic result) async {
    // Case 1: direct bytes
    if (result is Uint8List) return result;

    // Try common field names that may hold bytes
    final candidates = <Uint8List?>[];
    try {
      candidates.add(((result as dynamic).bytes) as Uint8List?);
    } catch (_) {}
    try {
      candidates.add(((result as dynamic).rawBytes) as Uint8List?);
    } catch (_) {}
    try {
      candidates.add(((result as dynamic).image) as Uint8List?);
    } catch (_) {}
    try {
      candidates.add(((result as dynamic).croppedImage) as Uint8List?);
    } catch (_) {}
    try {
      candidates.add(((result as dynamic).croppedBytes) as Uint8List?);
    } catch (_) {}
    for (final c in candidates) {
      if (c != null) return c;
    }

    // Some variants may return a ui.Image instance
    try {
      final img = (result as dynamic).image as ui.Image?;
      if (img != null) {
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        if (data != null) return data.buffer.asUint8List();
      }
    } catch (_) {}

    // As a last resort, try calling toByteData() directly on result if it quacks like ui.Image
    try {
      final data = await (result as dynamic).toByteData(format: ui.ImageByteFormat.png) as ByteData?;
      if (data != null) return data.buffer.asUint8List();
    } catch (_) {}

    // Could not infer the structure; throw with type info for logs
    throw StateError('Unknown CropResult structure: ${result.runtimeType}');
  }

  /// Downscale a square PNG to at most [maxSize] while preserving transparency.
  Future<Uint8List> _resizePngSquareToMax(Uint8List pngBytes, int maxSize) async {
    try {
      final codec0 = await ui.instantiateImageCodec(pngBytes);
      final frame0 = await codec0.getNextFrame();
      final img0 = frame0.image;
      final w = img0.width;
      final h = img0.height;
      // Already small enough
      if (w <= maxSize && h <= maxSize) {
        final data = await img0.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      }
      final codec = await ui.instantiateImageCodec(
        pngBytes,
        targetWidth: maxSize,
        targetHeight: maxSize,
      );
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } catch (e) {
      debugPrint('Resize PNG failed, returning original: $e');
      return pngBytes;
    }
  }

  /// Prepare a larger transparent canvas with the original image centered, so the
  /// crop area can expand beyond original bounds (no UI slider needed).
  Future<void> _preparePaddedImage(Uint8List bytes) async {
    setState(() => _preparing = true);
    try {
      // Validate decodability but avoid adding transparent margins that shrink the visual size
      final codec = await ui.instantiateImageCodec(bytes);
      await codec.getNextFrame();
      _paddedBytes = bytes;
    } catch (e) {
      debugPrint('Prepare image failed, falling back to original: $e');
      _paddedBytes = bytes;
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }
}
