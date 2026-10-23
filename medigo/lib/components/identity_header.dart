import 'package:flutter/material.dart';
import 'package:medigo/theme.dart';
import 'dart:typed_data';

/// Identity header for a drug/presentation. Shows title, forme, optional CIP and price,
/// and a lab initials avatar derived from the manufacturer name.
class IdentityHeader extends StatelessWidget {
  final String title;
  final String? forme;
  final String? manufacturer;
  final String? cip13;
  final double? price;
  final Uint8List? avatarImageBytes;
  final VoidCallback? onAvatarTap;
    /// Optional trailing widget, rendered at the top-right corner of the card
    /// (e.g., an edit IconButton for manual drugs).
    final Widget? trailing;

  const IdentityHeader({super.key, required this.title, this.forme, this.manufacturer, this.cip13, this.price, this.avatarImageBytes, this.onAvatarTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final m = (manufacturer ?? '').trim();
    final hasCip = (cip13 != null && cip13!.trim().isNotEmpty);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(gradient: AppGradients.surfaceTint(cs)),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(imageBytes: avatarImageBytes, initialsSource: m, onTap: onAvatarTap),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t.titleLarge, softWrap: true, overflow: TextOverflow.visible),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if ((forme ?? '').trim().isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                                child: Text((forme ?? '').trim(), style: t.labelMedium?.copyWith(color: cs.onSurface)),
                              ),
                            if (hasCip)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: cs.secondary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                                child: Text('CIP: ${cip13!.trim()}', style: t.labelMedium?.copyWith(color: cs.onSurface)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.factory, size: 16, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                m.isNotEmpty ? m : 'Laboratoire inconnu',
                                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                        if (price != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.euro, size: 18, color: cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text('${price!.toStringAsFixed(2)} €', style: t.bodyMedium),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              Positioned(
                right: 4,
                top: 4,
                child: trailing!,
              ),
          ],
        ),
      ),
    );
  }
}

/// Circular avatar with manufacturer initials. Parenthesis are ignored entirely when building initials.
class LabInitialsAvatar extends StatelessWidget {
  final String name;
  const LabInitialsAvatar({super.key, required this.name});

  String _initials(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '?';
    // Remove any parenthetical content and parentheses characters
    s = s.replaceAll(RegExp(r"\([^)]*\)"), '');
    s = s.replaceAll(RegExp(r"[()\[\]{}]"), '');
    // Keep only letters (including accents) as word characters; replace others with spaces
    s = s.replaceAll(RegExp(r"[^A-Za-zÀ-ÖØ-öø-ÿ]+"), ' ').trim();
    if (s.isEmpty) return '?';
    final parts = s.split(RegExp(r"\s+")).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      final one = parts.first;
      return one.length >= 2 ? (one[0] + one[1]).toUpperCase() : one[0].toUpperCase();
    }
    final first = parts.first[0];
    final last = parts.last[0];
    final combo = (first + last).toUpperCase();
    return combo.isNotEmpty ? combo : '?';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final text = _initials(name);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(text, style: t.titleMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
    );
  }
}

/// Internal avatar that shows either an imported image or the LabInitialsAvatar.
class _Avatar extends StatelessWidget {
  final Uint8List? imageBytes;
  final String initialsSource;
  final VoidCallback? onTap;

  const _Avatar({required this.imageBytes, required this.initialsSource, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>();
    Widget content;
    if (imageBytes != null && imageBytes!.isNotEmpty) {
      // Render the logo fully visible within the circular area on a light surface
      content = Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: appColors?.labLogoBackground, // white background for transparent logos
          shape: BoxShape.circle,
          border: Border.all(color: cs.outline.withValues(alpha: 0.24), width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: Image.memory(imageBytes!, gaplessPlayback: true),
          ),
        ),
      );
    } else {
      content = LabInitialsAvatar(name: initialsSource);
    }
    if (onTap != null) return InkWell(borderRadius: BorderRadius.circular(28), onTap: onTap, child: content);
    return content;
  }
}
