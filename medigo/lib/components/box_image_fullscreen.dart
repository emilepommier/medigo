import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Full-screen viewer for a drug box image with pinch-zoom and pan.
/// Opens via [BoxImageFullscreen.show]. Accepts either in-memory bytes or a URL.
class BoxImageFullscreen extends StatelessWidget {
  final Uint8List? imageBytes;
  final String? imageUrl;
  const BoxImageFullscreen({super.key, this.imageBytes, this.imageUrl});

  static Future<void> show(BuildContext context, {Uint8List? bytes, String? url}) async {
    if ((bytes == null || bytes.isEmpty) && (url == null || url.isEmpty)) return;
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => BoxImageFullscreen(imageBytes: bytes, imageUrl: url),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final image = imageBytes != null
        ? Image.memory(imageBytes!, fit: BoxFit.contain)
        : Image.network(imageUrl!, fit: BoxFit.contain);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            // Tapping anywhere outside the image dismisses the viewer
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            Positioned.fill(
              child: InteractiveViewer(
                panEnabled: true,
                scaleEnabled: true,
                minScale: 1,
                maxScale: 5,
                boundaryMargin: const EdgeInsets.all(96),
                clipBehavior: Clip.none,
                child: Center(child: image),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: cs.surface.withValues(alpha: 0.6),
                ),
                icon: Icon(Icons.close, color: cs.onSurface),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Fermer',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
