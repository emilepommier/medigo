import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/services/pharmacie_store.dart';
import 'package:medigo/screens/scan_cip_page.dart';
import 'package:medigo/services/cip_parser.dart';
import 'package:medigo/screens/drug_detail_screen.dart';
import 'package:medigo/screens/presentation_detail_screen.dart';
import 'package:medigo/utils/drug_text.dart';

class PharmacieScreen extends StatefulWidget {
  const PharmacieScreen({super.key});

  @override
  State<PharmacieScreen> createState() => _PharmacieScreenState();
}

class _PharmacieScreenState extends State<PharmacieScreen> {
  List<InventoryItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _items = await PharmacieStore.load();
    } catch (e) {
      debugPrint('Failed to load pharmacie items: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _promptAddItem() async {
    final cipController = TextEditingController();
    final qtyController = TextEditingController(text: '1');
    final result = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ajouter un médicament', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: cipController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'CIP',
                  prefixIcon: const Icon(Icons.qr_code),
                  suffixIcon: IconButton(
                    tooltip: 'Scanner',
                    icon: const Icon(Icons.qr_code_scanner, color: Colors.blue),
                    onPressed: () async {
                      final parsed = await Navigator.of(context).push<CipParseResult>(
                        MaterialPageRoute(builder: (_) => const ScanCipPage()),
                      );
                      if (parsed == null) return;
                      if (parsed.cip13 != null) {
                        cipController.text = parsed.cip13!;
                      } else if (parsed.cip7 != null) {
                        // Try to resolve CIP7 -> CIP13 from database
                        try {
                          final res = await SupabaseConfig.client
                              .from('presentations')
                              .select('cip13')
                              .eq('cip7', parsed.cip7!)
                              .limit(1);
                          if (res is List && res.isNotEmpty) {
                            final c = (res.first as Map<String, dynamic>)['cip13'] as String?;
                            if (c != null) {
                              cipController.text = c;
                            }
                          }
                        } catch (e) {
                          debugPrint('Resolve CIP7 to CIP13 failed: $e');
                        }
                      } else {
                        // try any 13 digits inside raw
                        final re = RegExp(r'(34009\d{8})');
                        final m = re.firstMatch(parsed.raw);
                        if (m != null) {
                          cipController.text = m.group(1)!;
                        }
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantité',
                  prefixIcon: Icon(Icons.numbers),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter'),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (result == true) {
      final cip13 = cipController.text.trim();
      final qty = int.tryParse(qtyController.text.trim());
      if (cip13.isNotEmpty && qty != null) {
        await PharmacieStore.addOrIncrement(cip13, by: qty);
        _items = await PharmacieStore.load();
        setState(() {});
      }
    }
  }

  Future<Map<String, dynamic>?> _loadPresentation(String cip13) async {
    try {
      final res = await SupabaseConfig.client
          .from('presentations')
          .select('cip13,cip7,libelle,prix_euro,cis,drugs(denomination,forme,titulaires)')
          .eq('cip13', cip13)
          .maybeSingle();
      return res as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('Failed to load presentation $cip13: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final parsed = await Navigator.of(context).push<CipParseResult>(
                  MaterialPageRoute(builder: (_) => const ScanCipPage()),
                );
                if (parsed == null) return;
                String? cip13 = parsed.cip13;
                if (cip13 == null && parsed.cip7 != null) {
                  try {
                    final res = await SupabaseConfig.client
                        .from('presentations')
                        .select('cip13')
                        .eq('cip7', parsed.cip7!)
                        .limit(1);
                    if (res is List && res.isNotEmpty) {
                      cip13 = (res.first as Map<String, dynamic>)['cip13'] as String?;
                    }
                  } catch (e) {
                    debugPrint('Resolve CIP7->CIP13 failed: $e');
                  }
                }
                if (cip13 != null) {
                  await PharmacieStore.addOrIncrement(cip13, by: 1);
                  _items = await PharmacieStore.load();
                  if (mounted) setState(() {});
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Médicament ajouté à votre pharmacie.')),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Aucun CIP valide détecté.')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scanner un code'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _promptAddItem,
              icon: const Icon(Icons.add_circle),
              label: const Text('Ajouter un médicament par CIP'),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('Votre pharmacie est vide.'))
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Dismissible(
                        key: ValueKey(item.cip13),
                        background: Container(
                          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: const Icon(Icons.delete, color: Colors.red),
                        ),
                        secondaryBackground: Container(
                          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: const Icon(Icons.delete, color: Colors.red),
                        ),
                        onDismissed: (_) async {
                          await PharmacieStore.remove(item.cip13);
                          _items = await PharmacieStore.load();
                          setState(() {});
                        },
                        child: FutureBuilder<Map<String, dynamic>?>(
                          future: _loadPresentation(item.cip13),
                          builder: (context, snapshot) {
                            final data = snapshot.data;
                            final denomRaw = data != null && data['drugs'] != null ? (data['drugs']['denomination'] as String? ?? '') : '';
                            final forme = data != null && data['drugs'] != null ? (data['drugs']['forme'] as String? ?? '') : '';
                            final denom = DrugTextUtils.sanitizeDenomination(denomRaw, forme);
                            final libelle = data != null ? (data['libelle'] as String? ?? '') : '';
                            final label = denom.isNotEmpty ? denom : libelle;
                            // final cis = data != null ? (data['cis'] as num?)?.toInt() : null;
                            // Manufacturer from drugs.titulaires (array)
                            String manufacturer = '';
                            if (data != null && data['drugs'] != null) {
                              final d = data['drugs'] as Map<String, dynamic>;
                              if (d['titulaires'] is List && (d['titulaires'] as List).isNotEmpty) {
                                manufacturer = ((d['titulaires'] as List).first ?? '').toString();
                              }
                            }
                            return Card(
                              child: ListTile(
                                onTap: () {
                                  // Navigate to presentation-specific management page
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PresentationDetailScreen(cip13: item.cip13),
                                    ),
                                  );
                                },
                                leading: const Icon(Icons.medication_outlined, color: Colors.blue),
                                title: Text(label),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (manufacturer.isNotEmpty) Text(manufacturer),
                                    // Show full CIP (cip13)
                                    Text('CIP: ${item.cip13}'),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, color: Colors.orange),
                                       onPressed: () async {
                                        await PharmacieStore.decrementOrRemove(item.cip13);
                                        _items = await PharmacieStore.load();
                                        setState(() {});
                                       },
                                    ),
                                    Text('x${item.quantity}'),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                       onPressed: () async {
                                        await PharmacieStore.addOrIncrement(item.cip13, by: 1);
                                        _items = await PharmacieStore.load();
                                        setState(() {});
                                       },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// InventoryItem is provided by PharmacieStore
