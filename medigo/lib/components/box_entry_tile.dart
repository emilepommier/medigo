import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:medigo/theme.dart';
import 'package:medigo/services/pharmacie_store.dart';

class BoxEntryTile extends StatelessWidget {
  final InventoryEntry entry;
  final VoidCallback onEditExpiry;
  final VoidCallback onDelete;
  final int? index;

  const BoxEntryTile(
      {super.key,
      required this.entry,
      required this.onEditExpiry,
      required this.onDelete,
      this.index});

  String _formatFull(DateTime? d) {
    if (d == null) return '—';
    try {
      return DateFormat('dd/MM/yyyy').format(d.toLocal());
    } catch (_) {
      return d.toLocal().toIso8601String();
    }
  }

  String _formatMonthYear(DateTime? d) {
    if (d == null) return '—';
    try {
      final dt = d.toLocal();
      const months = [
        'Jan',
        'Fév',
        'Mar',
        'Avr',
        'Mai',
        'Juin',
        'Juil',
        'Aoû',
        'Sep',
        'Oct',
        'Nov',
        'Déc'
      ];
      final m = (dt.month >= 1 && dt.month <= 12)
          ? months[dt.month - 1]
          : DateFormat('MMM', 'fr_FR').format(dt);
      return '$m ${dt.year}';
    } catch (_) {
      final dt = d.toLocal();
      return '${dt.month.toString().padLeft(2, '0')} ${dt.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final ex = entry.expiresAt;
    bool expired = false;
    bool expiring = false;
    if (ex != null) {
      final eKey = ex.year * 100 + ex.month;
      final nKey = now.year * 100 + now.month;
      expired = eKey < nKey;
      expiring = eKey == nKey;
    }

    // Build small expiry badge to sit before the trailing menu
    Widget expiryBadge() {
      if (ex == null) return const SizedBox.shrink();
      // Only show when expired or about to expire (same month)
      if (!expired && !expiring) return const SizedBox.shrink();
      Color fg;
      Color bg;
      String label;
      if (expired) {
        fg = cs.error;
        bg = cs.error.withValues(alpha: 0.10);
        label = 'Expiré';
      } else {
        final app = Theme.of(context).extension<AppColors>();
        fg = (app?.warning) ?? cs.tertiary;
        bg = ((app?.warning) ?? cs.tertiary).withValues(alpha: 0.12);
        label = 'Expire bientôt';
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            style:
                t.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        leading: index != null
            ? SizedBox(
                width: 24,
                child: Center(
                    child:
                        Text('${index! + 1}', style: t.titleMedium?.semiBold)))
            : null,
        title: Text(
          'Péremption: ${_formatMonthYear(entry.expiresAt)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.titleMedium,
        ),
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Ajoutée le ${_formatFull(entry.addedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            expiryBadge(),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEditExpiry();
                    break;
                  case 'delete':
                    onDelete();
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                    value: 'edit', child: Text('Modifier la péremption')),
                PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
