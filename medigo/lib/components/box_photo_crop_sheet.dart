import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:medigo/theme.dart';

/// Bottom sheet to crop a drug box image to a 16:9 rectangle (matches BoxPhotoPlaceholder)
/// Returns cropped PNG bytes via Navigator.pop(bytes). If cancelled, returns null.
class BoxPhotoCropSheet extends StatefulWidget {
  final Uint8List imageBytes;
  const BoxPhotoCropSheet({super.key, required this.imageBytes});

  static Future<Uint8List?> show(BuildContext context, Uint8List bytes) async {
    return await showModalBottomSheet<Uint8List?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: BoxPhotoCropSheet(imageBytes: bytes),
      ),
    );
  }

  @override
  State<BoxPhotoCropSheet> createState() => _BoxPhotoCropSheetState();
}

class _BoxPhotoCropSheetState extends State<BoxPhotoCropSheet> {
  final _controller = CropController();
  Uint8List? _paddedBytes;
  bool _preparing = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _preparePaddedImage(widget.imageBytes);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final screen = MediaQuery.sizeOf(context);

    final paddingH = 8.0;
    final availableW = (screen.width - paddingH).clamp(260.0, 1600.0);
    final availableH =
        (screen.height * 0.7).clamp(220.0, screen.height - 160.0);
    // Choose the limiting dimension for a 16:9 frame in the available area
    final widthByHeight = availableH * (16 / 9);
    final cropW = widthByHeight <= availableW ? widthByHeight : availableW;
    final cropH = cropW * (9 / 16);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Recadrer la boîte', style: t.titleLarge),
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: cropW,
                height: cropH,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(width: 0.1, color: cs.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: _preparing
                        ? const Center(child: CircularProgressIndicator())
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 36, horizontal: 64),
                            child: Crop(
                              image: _paddedBytes!,
                              withCircleUi: false,
                              aspectRatio: 16 / 9,
                              controller: _controller,
                              // Make the frame clearly visible
                              baseColor: cs.surfaceContainerHighest,
                              maskColor: cs.scrim.withValues(alpha: 0.5),
                              // Make corner handles smaller; visual size matches actual tap radius
                              radius: 7,
                              cornerDotBuilder: (size, edgeAlignment) {
                                return Container(
                                  width: size,
                                  height: size,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: cs.primary,
                                    border: Border.all(
                                        color: cs.onPrimary, width: 2),
                                  ),
                                );
                              },
                              onCropped: (result) async {
                                try {
                                  final bytes =
                                      await _extractCroppedBytes(result);
                                  final normalized = await _resizePngToMax(
                                      bytes,
                                      maxWidth: 1600,
                                      maxHeight: 1600);
                                  if (mounted) {
                                    Navigator.of(context).pop(normalized);
                                  }
                                } catch (e) {
                                  debugPrint(
                                      'BoxPhotoCrop: onCropped failed: $e');
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
            Row(
              children: [
                TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Annuler')),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saving ? null : _onSave,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.crop),
                  label: Text(_saving ? 'Traitement...' : 'Recadrer'),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    setState(() => _saving = true);
    try {
      _controller.crop();
    } catch (e) {
      debugPrint('BoxPhotoCrop: save failed: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _preparePaddedImage(Uint8List bytes) async {
    setState(() => _preparing = true);
    try {
      // Validate decodability then minimally pad to a 16:9 transparent canvas
      final codec = await ui.instantiateImageCodec(bytes);
      await codec.getNextFrame();
      _paddedBytes = await _padToAspect16x9(bytes);
    } catch (e) {
      debugPrint('BoxPhotoCrop: prepare image failed, using original: $e');
      _paddedBytes = bytes;
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  // Create a minimal 16:9 transparent canvas that fully contains the source image.
  // This lets the crop area expand to the full 16:9 frame beyond the original edges.
  Future<Uint8List> _padToAspect16x9(Uint8List srcBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(srcBytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final w = img.width;
      final h = img.height;

      // Calculate two 16:9 canvas options:
      // Option 1: width-constrained (canvas width = image width)
      final option1W = w;
      final option1H = ((w * 9) / 16).ceil();

      // Option 2: height-constrained (canvas height = image height)
      final option2H = h;
      final option2W = ((h * 16) / 9).ceil();

      // Choose the option that contains the entire image
      final bool useOption1 = option1H >= h;
      final minTargetW = useOption1 ? option1W : option2W;
      final minTargetH = useOption1 ? option1H : option2H;

      // Add a small extra margin so crop can extend past edges even when the
      // source is already 16:9. Keep the same aspect ratio while scaling up.
      const scale = 1.12; // +12% canvas padding around
      final targetW = (minTargetW * scale).ceil();
      final targetH = (minTargetH * scale).ceil();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint();
      // Transparent background; draw image centered on the larger canvas
      final dx = ((targetW - w) / 2).toDouble();
      final dy = ((targetH - h) / 2).toDouble();
      canvas.drawImage(img, Offset(dx, dy), paint);
      final picture = recorder.endRecording();
      final composed = await picture.toImage(targetW, targetH);
      final data = await composed.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } catch (e) {
      debugPrint('BoxPhotoCrop: padToAspect16x9 failed: $e');
      return srcBytes;
    }
  }

  Future<Uint8List> _extractCroppedBytes(dynamic result) async {
    if (result is Uint8List) return result;
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
    try {
      final img = (result as dynamic).image as ui.Image?;
      if (img != null) {
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        if (data != null) return data.buffer.asUint8List();
      }
    } catch (_) {}
    try {
      final data = await (result as dynamic)
          .toByteData(format: ui.ImageByteFormat.png) as ByteData?;
      if (data != null) return data.buffer.asUint8List();
    } catch (_) {}
    throw StateError('Unknown CropResult structure: ${result.runtimeType}');
  }

  Future<Uint8List> _resizePngToMax(Uint8List pngBytes,
      {required int maxWidth, required int maxHeight}) async {
    try {
      final codec0 = await ui.instantiateImageCodec(pngBytes);
      final frame0 = await codec0.getNextFrame();
      final img0 = frame0.image;
      final w = img0.width;
      final h = img0.height;
      if (w <= maxWidth && h <= maxHeight) {
        final data = await img0.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      }
      // Compute target while preserving aspect ratio
      double tw = w.toDouble();
      double th = h.toDouble();
      final wr = maxWidth / tw;
      final hr = maxHeight / th;
      final r = wr < hr ? wr : hr;
      final targetW = (tw * r).round();
      final targetH = (th * r).round();
      final codec = await ui.instantiateImageCodec(pngBytes,
          targetWidth: targetW, targetHeight: targetH);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } catch (e) {
      debugPrint('BoxPhotoCrop: resize failed, returning original: $e');
      return pngBytes;
    }
  }
}
