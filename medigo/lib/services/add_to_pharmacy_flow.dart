import 'package:flutter/material.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/services/pharmacie_store.dart';
import 'package:medigo/components/month_year_picker_sheet.dart';
import 'package:medigo/services/notification_service.dart';

/// Centralized UX flow for adding a drug box to the user's pharmacy.
///
/// Rules:
/// - If only cip13 is provided: just ask for expiry date, then add that presentation.
/// - If only cis is provided: load its presentations. If >1, prompt user to choose;
///   if exactly 1, use it directly. Then ask for expiry date and add.
/// - If both are provided: prefer cis selection behavior when there are multiple
///   presentations for the cis. This ensures the user can switch presentation
///   if needed from search results.
class AddToPharmacyFlow {
  AddToPharmacyFlow._();

  static Future<bool> add({
    required BuildContext context,
    String? cip13,
    int? cis,
  }) async {
    try {
      String? finalCip = cip13;

      // If we have a cis, let user choose presentation when multiple exist.
      if (cis != null) {
        final presentations = await _loadPresentationsForCis(cis);
        if (presentations.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Aucune présentation disponible pour ce médicament.")),
          );
          return false;
        }
        if (presentations.length == 1) {
          finalCip = presentations.first['cip13'] as String?;
        } else {
          finalCip = await _promptChoosePresentation(context, presentations);
          if (finalCip == null) return false; // user canceled
        }
      }

      // If we still don't have a cip, abort.
      if (finalCip == null || finalCip.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("CIP introuvable.")),
        );
        return false;
      }

      // Ask for expiry month/year via bottom sheet. Cancel aborts the add flow.
      final picked = await MonthYearPickerSheet.show(context);
      if (picked == null) return false; // user canceled => do not add

      // Validate expiry
      final now = DateTime.now();
      final isExpired = NotificationService.isExpiredMonth(picked, now);
      final isThisMonth = NotificationService.isSameMonth(picked, now);
      if (isExpired) {
        final confirm = await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          builder: (ctx) {
            final cs = Theme.of(ctx).colorScheme;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(width: 40, height: 40, decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.warning_amber, color: cs.onErrorContainer)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Date de péremption dépassée', style: Theme.of(ctx).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text("Cette boîte est déjà expirée. Voulez-vous l'ajouter quand même ?", style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ])),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Non'))),
                      const SizedBox(width: 12),
                      Expanded(child: FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Oui'))),
                    ])
                  ],
                ),
              ),
            );
          },
        );
        if (confirm != true) return false;
      }

      await PharmacieStore.addOrIncrement(finalCip, by: 1, expiresAt: picked);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Boîte ajoutée à votre pharmacie.')),
        );
      }

      // Schedule notifications: month-start and immediate if current month
      try {
        await NotificationService.scheduleMonthNotification(cip13: finalCip, expiresAt: picked);
        if (isThisMonth) {
          await NotificationService.notifyIfCurrentMonth(cip13: finalCip, expiresAt: picked);
        }
      } catch (e) {
        debugPrint('Add flow schedule notifications failed: $e');
      }
      return true;
    } catch (e) {
      debugPrint('AddToPharmacyFlow.add failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible d'ajouter le médicament.")),
        );
      }
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> _loadPresentationsForCis(int cis) async {
    try {
      final res = await SupabaseConfig.client
          .from('presentations')
          .select('cip13,libelle,prix_euro')
          .eq('cis', cis)
          .order('libelle')
          .limit(200);
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Failed to load presentations for cis=$cis: $e');
      return [];
    }
  }

  static Future<String?> _promptChoosePresentation(
    BuildContext context,
    List<Map<String, dynamic>> presentations,
  ) async {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.view_list),
                    const SizedBox(width: 8),
                    Text('Choisir une présentation', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: presentations.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = presentations[i];
                    final lib = (p['libelle'] as String?) ?? 'Présentation';
                    final cip = (p['cip13'] as String?) ?? '';
                    final prix = p['prix_euro'];
                    return ListTile(
                      leading: const Icon(Icons.local_hospital, color: Colors.blue),
                      title: Text(lib, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('CIP: $cip'),
                      trailing: prix != null ? Text('${prix.toString()} €') : null,
                      onTap: () => Navigator.of(context).pop(cip),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
