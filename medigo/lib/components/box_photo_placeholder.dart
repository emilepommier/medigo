import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:medigo/theme.dart';
import 'package:medigo/components/box_image_fullscreen.dart';

/// Gradient placeholder for a drug box photo.
/// - Shows a lighter gradient when empty
/// - Displays the provided image bytes if available
/// - Can be tappable to trigger an import sheet
class BoxPhotoPlaceholder extends StatelessWidget {
  final Uint8List? imageBytes;
  final String? imageUrl; // secure signed URL
  final VoidCallback? onTap;
  const BoxPhotoPlaceholder({super.key, this.imageBytes, this.imageUrl, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasMemory = imageBytes != null && imageBytes!.isNotEmpty;
    final hasNetwork = (imageUrl != null && imageUrl!.isNotEmpty);
    Widget content = Container(
      decoration: BoxDecoration(
        gradient: (hasMemory || hasNetwork) ? null : AppGradients.imagePlaceholder(cs),
      ),
      child: hasMemory
          ? Image.memory(imageBytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
          : hasNetwork
              ? Image.network(imageUrl!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
              : const SizedBox.expand(),
    );
    content = InkWell(
      onTap: onTap,
      onLongPress: (hasMemory || hasNetwork)
          ? () => BoxImageFullscreen.show(context, bytes: imageBytes, url: imageUrl)
          : null,
      child: content,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(aspectRatio: 16 / 9, child: content),
    );
  }
}
