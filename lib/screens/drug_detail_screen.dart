import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:medigo/services/pharmacie_store.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/utils/drug_text.dart';

class DrugDetailScreen extends StatefulWidget {
  final int cis;
  const DrugDetailScreen({super.key, required this.cis});

  @override
  State<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends State<DrugDetailScreen> {
  Future<Map<String, dynamic>> _loadData() async {
    final client = SupabaseConfig.client;
    try {
      final drug = await client
          .from('drugs')
          .select(
              'cis,denomination,forme,voies,statut_amm,etat_commercialisation,date_amm,statut_bdm,titulaires,surveillance_renforcee')
          .eq('cis', widget.cis)
          .maybeSingle() as Map<String, dynamic>?;

      final presentations = await client
          .from('presentations')
          .select(
              'cip13,cip7,libelle,prix_euro,taux_remboursement,etat_commercialisation')
          .eq('cis', widget.cis)
          .order('libelle')
          .limit(200) as List<dynamic>;

      return {
        'drug': drug,
        'presentations': presentations,
      };
    } catch (e) {
      debugPrint('DrugDetail load failed: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail médicament'),
        centerTitle: true,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _loadData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Erreur de chargement', style: TextStyle(color: cs.error)),
              ),
            );
          }
          final data = snapshot.data ?? {};
          final drug = data['drug'] as Map<String, dynamic>?;
          final presentations = (data['presentations'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();

          final rawDenom = (drug?['denomination'] as String?) ?? '';
          final forme = (drug?['forme'] as String?) ?? '';
          final cleanDenom = DrugTextUtils.sanitizeDenomination(rawDenom, forme);
          String manufacturer = '';
          if (drug != null && drug['titulaires'] is List && (drug['titulaires'] as List).isNotEmpty) {
            manufacturer = ((drug['titulaires'] as List).first ?? '').toString();
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Placeholder for lab logo
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
                                Text(
                                  cleanDenom.isNotEmpty ? cleanDenom : 'Médicament',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  forme,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 6),
                                if (manufacturer.isNotEmpty)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.factory, size: 16, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(manufacturer, style: Theme.of(context).textTheme.bodySmall),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (drug?['etat_commercialisation'] != null)
                            Chip(
                              label: Text('État: ${drug?['etat_commercialisation']}'),
                            ),
                          if (drug?['statut_amm'] != null)
                            Chip(label: Text('AMM: ${drug?['statut_amm']}')),
                          if (drug?['surveillance_renforcee'] == true)
                            const Chip(
                              avatar: Icon(Icons.warning_amber, color: Colors.orange),
                              label: Text('Surveillance renforcée'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Présentations', style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
              SliverList.separated(
                itemCount: presentations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final p = presentations[index];
                          final cip13 = (p['cip13'] as String?) ?? '';
                          final libelle = (p['libelle'] as String?) ?? '';
                          final prix = p['prix_euro'];
                  return Padding(
                    padding: EdgeInsets.fromLTRB(16, index == 0 ? 8 : 0, 16, 0),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.local_hospital, color: Colors.blue),
                        title: Text(libelle.isNotEmpty ? libelle : 'Présentation'),
                        subtitle: Text('CIP: $cip13'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (prix != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Text('${prix.toString()} €', style: Theme.of(context).textTheme.labelLarge),
                              ),
                            IconButton(
                              tooltip: 'Ajouter à ma pharmacie',
                              icon: const Icon(Icons.add_circle, color: Colors.green),
                              onPressed: () async {
                                await PharmacieStore.addOrIncrement(cip13, by: 1);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Ajouté à votre pharmacie.')),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          );
        },
      ),
    );
  }
}
