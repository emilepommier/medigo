import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:medigo/theme.dart';

/// Bottom sheet that applies a predefined, uniform photo filter to drug box images.
/// Returns the filtered PNG bytes via Navigator.pop(bytes). If cancelled, returns null.
class DrugPhotoFilterSheet extends StatefulWidget {
  final Uint8List imageBytes;
  const DrugPhotoFilterSheet({super.key, required this.imageBytes});

  static Future<Uint8List?> show(BuildContext context, Uint8List bytes) async {
    return await showModalBottomSheet<Uint8List?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DrugPhotoFilterSheet(imageBytes: bytes),
      ),
    );
  }

  @override
  State<DrugPhotoFilterSheet> createState() => _DrugPhotoFilterSheetState();
}

class _DrugPhotoFilterSheetState extends State<DrugPhotoFilterSheet> {
  bool _processing = true;
  bool _showOriginal = false;
  Uint8List? _filteredBytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _applyUniformFilter(widget.imageBytes);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final screenHeight = MediaQuery.of(context).size.height;

    return SafeArea(
      child: Container(
        height: screenHeight * 0.86,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Uniformiser la photo", style: t.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: _processing
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline, color: cs.error, size: 40),
                                  const SizedBox(height: 8),
                                  Text(_error!, style: t.bodyMedium?.copyWith(color: cs.error)),
                                ],
                              ),
                            )
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                // Show filtered by default; allow press/hold to compare original
                                Image.memory(_showOriginal ? widget.imageBytes : (_filteredBytes ?? widget.imageBytes), fit: BoxFit.contain),
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Tooltip(
                                    message: _showOriginal ? 'Aperçu: original' : 'Aperçu: filtré',
                                    child: FilledButton.tonalIcon(
                                      onPressed: () => setState(() => _showOriginal = !_showOriginal),
                                      icon: Icon(_showOriginal ? Icons.visibility : Icons.visibility_off, color: cs.onSecondaryContainer),
                                      label: Text(_showOriginal ? 'Original' : 'Filtré'),
                                    ),
                                  ),
                                )
                              ],
                            ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: _processing ? null : () => Navigator.of(context).pop(null),
                  child: const Text('Annuler'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _processing || _filteredBytes == null ? null : () => Navigator.of(context).pop(_filteredBytes),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Appliquer'),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _applyUniformFilter(Uint8List input) async {
    setState(() {
      _processing = true;
      _error = null;
      _filteredBytes = null;
    });
    try {
      // Decode with codec to preserve transparency and quality
      final codec = await ui.instantiateImageCodec(input);
      final frame = await codec.getNextFrame();
      final srcImage = frame.image;

      // Render to an offscreen canvas with a color matrix filter applied
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high
        ..colorFilter = ColorFilter.matrix(_brannanMatrix());

      final srcRect = Rect.fromLTWH(0, 0, srcImage.width.toDouble(), srcImage.height.toDouble());
      canvas.drawImageRect(srcImage, srcRect, srcRect, paint);
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(srcImage.width, srcImage.height);
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      _filteredBytes = data!.buffer.asUint8List();
    } catch (e, st) {
      debugPrint('DrugPhotoFilter: failed to apply filter: $e\n$st');
      _error = "Échec de l'application du filtre";
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// A cooler, brighter matrix for uniform drug photo rendering.
  /// Red bias reduced, blue boosted, gentle lift in all channels.
  List<double> _brannanMatrix() {
    const rScale = 0.98;
    const gScale = 1.02;
    const bScale = 1.10;

    const crossRG = -0.02;
    const crossRB = -0.02;
    const crossGR = 0.00;
    const crossGB = 0.01;
    const crossBR = -0.01;
    const crossBG = 0.02;

    const lift = 0.04;

    return <double>[
      rScale, crossRG, crossRB, 0, lift,
      crossGR, gScale, crossGB, 0, lift,
      crossBR, crossBG, bScale, 0, lift,
      0.00, 0.00, 0.00, 1, 0.0,
    ];
  }
}
