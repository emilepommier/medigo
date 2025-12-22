import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:medigo/services/pharmacie_store.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/utils/drug_text.dart';

class PresentationDetailScreen extends StatefulWidget {
  final String cip13;
  const PresentationDetailScreen({super.key, required this.cip13});

  @override
  State<PresentationDetailScreen> createState() => _PresentationDetailScreenState();
}

class _PresentationDetailScreenState extends State<PresentationDetailScreen> {
  Map<String, dynamic>? _presentation;
  List<InventoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await SupabaseConfig.client
          .from('presentations')
          .select('cip13,cip7,libelle,prix_euro,cis,drugs(denomination,forme,titulaires)')
          .eq('cip13', widget.cip13)
          .maybeSingle();
      final entries = await PharmacieStore.loadEntries(widget.cip13);
      setState(() {
        _presentation = data as Map<String, dynamic>?;
        _entries = entries;
      });
    } catch (e) {
      debugPrint('Presentation detail load failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addBox() async {
    DateTime? expiry;
    // Pick expiry date (optional)
    expiry = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: 'Sélectionner la date de péremption (optionnel)',
    );
    await PharmacieStore.addEntry(widget.cip13, expiresAt: expiry);
    await PharmacieStore.addOrIncrement(widget.cip13, by: 1);
    await _load();
  }

  Future<void> _editExpiry(InventoryEntry entry) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: entry.expiresAt ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: 'Modifier la date de péremption',
    );
    if (picked != null) {
      await PharmacieStore.updateEntry(entry.id, entry.cip13, expiresAt: picked);
      await _load();
    }
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    try {
      return DateFormat('dd/MM/yyyy').format(d.toLocal());
    } catch (_) {
      return d.toLocal().toIso8601String();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final data = _presentation;
    final drugs = data != null ? (data['drugs'] as Map<String, dynamic>?) : null;
    final rawDenom = drugs != null ? (drugs['denomination'] as String? ?? '') : '';
    final forme = drugs != null ? (drugs['forme'] as String? ?? '') : '';
    final title = DrugTextUtils.sanitizeDenomination(rawDenom, forme);
    String manufacturer = '';
    if (drugs != null && drugs['titulaires'] is List && (drugs['titulaires'] as List).isNotEmpty) {
      manufacturer = ((drugs['titulaires'] as List).first ?? '').toString();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail présentation'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Ajouter une boîte',
            icon: const Icon(Icons.add_box, color: Colors.green),
            onPressed: _addBox,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Placeholder for laboratory logo
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.apartment, color: Colors.blue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title.isNotEmpty ? title : (data?['libelle'] as String? ?? 'Médicament'), style: t.titleLarge),
                              if (forme.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(forme, style: t.bodyMedium),
                                ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (manufacturer.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.factory, size: 16, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(manufacturer, style: t.bodySmall),
                                      ],
                                    ),
                                  Text('CIP: ${widget.cip13}', style: t.bodySmall),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Mes boîtes', style: t.titleLarge),
                        FilledButton.icon(
                          onPressed: _addBox,
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter une boîte'),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList.separated(
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final e = _entries[index];
                    return Padding(
                      padding: EdgeInsets.fromLTRB(16, index == 0 ? 8 : 0, 16, 0),
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.inventory_2_outlined, color: Colors.blue),
                          title: Text('Ajoutée le ${_formatDate(e.addedAt)}'),
                          subtitle: Text('Péremption: ${_formatDate(e.expiresAt)}'),
                          trailing: IconButton(
                            tooltip: 'Modifier la date de péremption',
                            icon: const Icon(Icons.edit_calendar, color: Colors.orange),
                            onPressed: () => _editExpiry(e),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (_entries.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Aucune boîte enregistrée pour cette présentation.'),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
    );
  }
}
