import 'package:flutter/material.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:go_router/go_router.dart';
import 'package:medigo/services/pharmacie_store.dart';
import 'package:medigo/screens/scan_cip_page.dart';
import 'package:medigo/services/cip_parser.dart';
import 'package:medigo/utils/drug_text.dart';

class RechercheScreen extends StatefulWidget {
  const RechercheScreen({super.key});

  @override
  State<RechercheScreen> createState() => _RechercheScreenState();
}

class _RechercheScreenState extends State<RechercheScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String _error = '';
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = '';
      _results = [];
    });
    try {
      final client = SupabaseConfig.client;
      final baseSelect = 'cip13,cip7,libelle,prix_euro,cis,drugs(denomination,forme)';
      final trimmed = q.trim();
      if (trimmed.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final isDigits = RegExp(r'^\d+$').hasMatch(trimmed);

      if (isDigits) {
        // Try exact CIP13 and CIP7
        final exact13 = await client
            .from('presentations')
            .select(baseSelect)
            .eq('cip13', trimmed)
            .limit(50);
        final exact7 = await client
            .from('presentations')
            .select(baseSelect)
            .eq('cip7', trimmed)
            .limit(50);
        // If nothing exact, try partial on cip13
        List<dynamic> partial = [];
        if ((exact13 as List).isEmpty && (exact7 as List).isEmpty) {
          partial = await client
              .from('presentations')
              .select(baseSelect)
              .ilike('cip13', '%$trimmed%')
              .limit(50);
        }
        final combined = <Map<String, dynamic>>[];
        combined.addAll((exact13 as List).cast<Map<String, dynamic>>());
        combined.addAll((exact7 as List).cast<Map<String, dynamic>>());
        combined.addAll((partial as List).cast<Map<String, dynamic>>());
        final seen = <String>{};
        _results = combined.where((e) => seen.add(e['cip13'] as String)).toList();
        setState(() {});
      } else {
        // Search by libellé
        final byLib = await client
            .from('presentations')
            .select(baseSelect)
            .ilike('libelle', '%$trimmed%')
            .limit(50);

        // Search by denomination in drugs, then load their presentations
        final drugs = await client
            .from('drugs')
            .select('cis,denomination,forme')
            .ilike('denomination', '%$trimmed%')
            .limit(20);
        final cisList = (drugs as List)
            .cast<Map<String, dynamic>>()
            .map((e) => e['cis'])
            .whereType<int>()
            .toList();
        List<dynamic> byDenom = [];
        if (cisList.isNotEmpty) {
          final futures = cisList.map((cis) {
            return client
                .from('presentations')
                .select(baseSelect)
                .eq('cis', cis)
                .limit(3);
          }).toList();
          final results = await Future.wait(futures);
          for (final r in results) {
            byDenom.addAll((r as List));
          }
        }
        final combined = <Map<String, dynamic>>[];
        combined.addAll((byLib as List).cast<Map<String, dynamic>>());
        combined.addAll((byDenom as List).cast<Map<String, dynamic>>());
        final seen = <String>{};
        _results = combined.where((e) => seen.add(e['cip13'] as String)).toList();
        setState(() {});
      }
    } catch (e) {
      setState(() => _error = 'Erreur lors de la recherche');
      debugPrint('Search error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: 'Rechercher par CIP ou nom...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Scanner un code',
                icon: const Icon(Icons.qr_code_scanner, color: Colors.blue),
                onPressed: () async {
                  final parsed = await Navigator.of(context).push<CipParseResult>(
                    MaterialPageRoute(builder: (_) => const ScanCipPage()),
                  );
                  if (parsed == null) return;
                  final query = parsed.cip13 ?? parsed.cip7 ?? parsed.raw;
                  _controller.text = query;
                  await _search(query);
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(_error, style: TextStyle(color: cs.error)),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      'Aucun résultat',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = _results[index];
                      final drugs = row['drugs'] as Map<String, dynamic>?;
                      final denomRaw = drugs != null ? (drugs['denomination'] as String? ?? '') : '';
                      final forme = drugs != null ? (drugs['forme'] as String? ?? '') : '';
                      final denom = DrugTextUtils.sanitizeDenomination(denomRaw, forme);
                      final libelle = (row['libelle'] as String?) ?? '';
                      final cip13 = (row['cip13'] as String?) ?? '';
                      final cip7 = (row['cip7'] as String?) ?? '';
                      final prix = row['prix_euro'];
                      return Card(
                        child: ListTile(
                          onTap: () {
                            final cis = row['cis'];
                            if (cis != null) {
                              context.push('/drug/$cis');
                            }
                          },
                          leading: const Icon(Icons.medication, color: Colors.blue),
                          title: Text(denom.isNotEmpty ? denom : libelle),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (denom.isNotEmpty && libelle.isNotEmpty)
                                Text(libelle, maxLines: 2, overflow: TextOverflow.ellipsis),
                              Text(forme, maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text('CIP: $cip13'),
                            ],
                          ),
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
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
