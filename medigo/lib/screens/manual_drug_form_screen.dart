import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:medigo/services/pharmacie_store.dart';
import 'package:medigo/components/month_year_picker_sheet.dart';
import 'package:medigo/services/notification_service.dart';

class ManualDrugFormScreen extends StatefulWidget {
  const ManualDrugFormScreen({super.key});

  @override
  State<ManualDrugFormScreen> createState() => _ManualDrugFormScreenState();
}

class _ManualDrugFormScreenState extends State<ManualDrugFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _labCtrl = TextEditingController();
  final _formeCtrl = TextEditingController();
  DateTime? _expiry;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _labCtrl.dispose();
    _formeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await MonthYearPickerSheet.show(context);
    if (picked != null) setState(() => _expiry = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_expiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Veuillez choisir une date de péremption.')));
      return;
    }
    // Warn if expired month
    final now = DateTime.now();
    final isExpired = NotificationService.isExpiredMonth(_expiry!, now);
    final isThisMonth = NotificationService.isSameMonth(_expiry!, now);
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
                    Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.warning_amber,
                            color: cs.onErrorContainer)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Date de péremption dépassée',
                              style: Theme.of(ctx).textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text(
                              "Cette boîte est déjà expirée. Voulez-vous l'ajouter quand même ?",
                              style: Theme.of(ctx)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                        ])),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Non'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Oui'))),
                  ])
                ],
              ),
            ),
          );
        },
      );
      if (confirm != true) return;
    }
    setState(() => _submitting = true);
    try {
      final key = await PharmacieStore.addCustomManualItem(
        name: _nameCtrl.text.trim(),
        laboratory: _labCtrl.text.trim(),
        forme: _formeCtrl.text.trim(),
        expiresAt: _expiry!,
      );
      if (!mounted) return;
      if (key != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Médicament ajouté.')));
        // Schedule notifications (custom keys also use cip13-like key)
        try {
          await NotificationService.scheduleMonthNotification(
              cip13: key,
              expiresAt: _expiry!,
              drugLabel: _nameCtrl.text.trim());
          if (isThisMonth) {
            await NotificationService.notifyIfCurrentMonth(
                cip13: key,
                expiresAt: _expiry!,
                drugLabel: _nameCtrl.text.trim());
          }
        } catch (e) {
          debugPrint('Manual add schedule notifications failed: $e');
        }
        // Return to Home page
        context.go('/');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Échec de l'ajout du médicament.")));
      }
    } catch (e) {
      debugPrint('ManualDrugFormScreen submit failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur lors de la création.')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajout manuel')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo placeholder
              Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_a_photo, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      Text('Ajouter une photo (bientôt)',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nom du médicament',
                  prefixIcon: Icon(Icons.medication_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _labCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Laboratoire',
                  prefixIcon: Icon(Icons.factory_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _formeCtrl,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Forme',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event),
                    label: Text(_expiry == null
                        ? 'Mois/année de péremption'
                        : _formatDate(_expiry!)),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: const Icon(Icons.save),
                  label: _submitting
                      ? const Text('Enregistrement...')
                      : const Text('Ajouter à la pharmacie'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final dt = d.toLocal();
    final mm = dt.month.toString().padLeft(2, '0');
    return '$mm/${dt.year}';
  }
}
