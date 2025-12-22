import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:medigo/supabase/supabase_config.dart';

typedef ProgressCallback = void Function(double progress, String step);

class BdpmImporter {
  static const String _cisFile = 'drug-database/CIS_bdpm.txt';
  static const String _cisCipFile = 'drug-database/CIS_CIP_bdpm.txt';

  final SupabaseClient _client = SupabaseConfig.client;

  Future<void> importAll({ProgressCallback? onProgress}) async {
    final stopwatch = Stopwatch()..start();
    try {
      // Require authentication for imports (RLS policies grant to authenticated users)
      final user = SupabaseConfig.auth.currentUser;
      if (user == null) {
        throw Exception('Vous devez être connecté pour exécuter l\'import BDPM.');
      }

      onProgress?.call(0.01, 'Chargement du fichier CIS...');
      final cisLines = await _loadTextLines(_cisFile);
      debugPrint('[BDPM] CIS lines: ${cisLines.length}');

      onProgress?.call(0.1, 'Analyse des spécialités (CIS)...');
      final drugs = _parseCisFile(cisLines);
      debugPrint('[BDPM] Parsed drugs: ${drugs.length}');

      // Upsert drugs in batches
      await _upsertInBatches(
        table: 'drugs',
        rows: drugs,
        onConflict: 'cis',
        onProgress: (p) => onProgress?.call(0.1 + p * 0.35, 'Insertion des spécialités...'),
      );

      onProgress?.call(0.5, 'Chargement du fichier CIS_CIP...');
      final cisCipLines = await _loadTextLines(_cisCipFile);
      debugPrint('[BDPM] CIS_CIP lines: ${cisCipLines.length}');

      onProgress?.call(0.55, 'Analyse des présentations (CIP)...');
      final presentations = _parseCisCipFile(cisCipLines);
      debugPrint('[BDPM] Parsed presentations: ${presentations.length}');

      await _upsertInBatches(
        table: 'presentations',
        rows: presentations,
        onConflict: 'cip13',
        onProgress: (p) => onProgress?.call(0.55 + p * 0.40, 'Insertion des présentations...'),
      );

      // Use a fixed well-known UUID for the single metadata row
      const metadataId = '00000000-0000-0000-0000-000000000001';
      await _client.from('drug_metadata').upsert({
        'id': metadataId,
        'last_imported_at': DateTime.now().toUtc().toIso8601String(),
        'source': 'BDPM',
        'count_drugs': drugs.length,
        'count_presentations': presentations.length,
      }, onConflict: 'id');

      onProgress?.call(1.0, 'Terminé en ${stopwatch.elapsed.inSeconds}s');
    } catch (e, st) {
      debugPrint('[BDPM] Import failed: $e\n$st');
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  Future<List<String>> _loadTextLines(String assetPath) async {
    // Load as bytes to support latin1 files, then attempt UTF-8 first
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = const Latin1Codec().decode(bytes);
    }
    // Normalize line endings and split
    return content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n').where((l) => l.trim().isNotEmpty).toList();
  }

  List<Map<String, dynamic>> _parseCisFile(List<String> lines) {
    // Expected columns (tab-separated) from CIS_bdpm.txt:
    // 0: Code CIS
    // 1: Dénomination du médicament
    // 2: Forme pharmaceutique
    // 3: Voies d'administration (";" separated)
    // 4: Statut administratif de l’AMM
    // 5: Type de procédure d'AMM
    // 6: Etat de commercialisation
    // 7: Date d’AMM (JJ/MM/AAAA)
    // 8: StatutBdm
    // 9: Numéro de l’autorisation européenne
    // 10: Titulaire(s) (";" separated)
    // 11: Surveillance renforcée (Oui/Non)
    final rows = <Map<String, dynamic>>[];
    for (final line in lines) {
      final cols = line.split('\t');
      if (cols.isEmpty || cols[0].trim().isEmpty) continue;
      // Some files might include a header row; skip if first column isn't numeric
      if (cols[0].trim().toLowerCase() == 'cis' || cols[0].contains('Code CIS')) continue;
      try {
        final cis = int.tryParse(cols[0].trim());
        if (cis == null) continue;
        final denomination = _safe(cols, 1);
        final forme = _safe(cols, 2);
        final voies = _splitList(_safe(cols, 3));
        final statutAmm = _safe(cols, 4);
        // final typeProcedure = _safe(cols, 5); // deprecated column in schema
        final etatComm = _safe(cols, 6);
        final dateAmm = _parseFrDate(_safe(cols, 7));
        final statutBdm = _safe(cols, 8);
        final numEu = _safe(cols, 9);
        final titulaires = _splitList(_safe(cols, 10));
        final surv = _toBool(_safe(cols, 11));

        rows.add({
          'cis': cis,
          'denomination': denomination,
          'forme': forme.isEmpty ? null : forme,
          'voies': voies.isEmpty ? null : voies,
          'statut_amm': statutAmm.isEmpty ? null : statutAmm,
          // 'type_procedure_amm': typeProcedure.isEmpty ? null : typeProcedure, // removed from schema
          'etat_commercialisation': etatComm.isEmpty ? null : etatComm,
          'date_amm': dateAmm,
          'statut_bdm': statutBdm.isEmpty ? null : statutBdm,
          'numero_autorisation_europeenne': numEu.isEmpty ? null : numEu,
          'titulaires': titulaires.isEmpty ? null : titulaires,
          'surveillance_renforcee': surv,
        });
      } catch (e) {
        debugPrint('[BDPM] Skip CIS row due to parse error: $e | $line');
      }
    }
    return rows;
  }

  List<Map<String, dynamic>> _parseCisCipFile(List<String> lines) {
    // Expected columns (tab-separated) from CIS_CIP_bdpm.txt:
    // 0: Code CIS
    // 1: Code CIP7
    // 2: Libellé de la présentation
    // 3: Statut administratif de la présentation
    // 4: Etat de commercialisation
    // 5: Date de la déclaration de commercialisation (JJ/MM/AAAA)
    // 6: Code CIP13
    // 7: Agrément aux collectivités (oui/non/inconnu)
    // 8: Taux de remboursement (";" separated)
    // 9: Prix en euro
    // 10: Texte indications de remboursement (si plusieurs taux)
    final rows = <Map<String, dynamic>>[];
    for (final line in lines) {
      final cols = line.split('\t');
      if (cols.isEmpty || cols[0].trim().isEmpty) continue;
      if (cols[0].trim().toLowerCase() == 'cis' || cols[0].contains('Code CIS')) continue;
      try {
        final cis = int.tryParse(cols[0].trim());
        if (cis == null) continue;
        final cip7 = _safe(cols, 1);
        final libelle = _safe(cols, 2);
        final statutAdmin = _safe(cols, 3);
        final etatComm = _safe(cols, 4);
        // final dateDecl = _parseFrDate(_safe(cols, 5)); // deprecated column in schema
        final cip13 = _safe(cols, 6);
        // final agrement = _safe(cols, 7); // deprecated column in schema
        final taux = _splitList(_safe(cols, 8));
        final prix = _parsePrice(_safe(cols, 9));
        // final indications = _safe(cols, 10); // deprecated column in schema

        if (cip13.isEmpty) continue; // require primary key

        rows.add({
          'cis': cis,
          'cip7': cip7.isEmpty ? null : cip7,
          'libelle': libelle.isEmpty ? null : libelle,
          'statut_admin': statutAdmin.isEmpty ? null : statutAdmin,
          'etat_commercialisation': etatComm.isEmpty ? null : etatComm,
          // 'date_declaration': dateDecl,
          'cip13': cip13,
          // 'agrement_collectivites': agrement.isEmpty ? null : agrement,
          'taux_remboursement': taux.isEmpty ? null : taux,
          'prix_euro': prix,
          // 'indications_remboursement': indications.isEmpty ? null : indications,
        });
      } catch (e) {
        debugPrint('[BDPM] Skip CIS_CIP row due to parse error: $e | $line');
      }
    }
    return rows;
  }

  Future<void> _upsertInBatches({
    required String table,
    required List<Map<String, dynamic>> rows,
    required String onConflict,
    int batchSize = 500,
    void Function(double p)? onProgress,
  }) async {
    if (rows.isEmpty) return;
    final total = rows.length;
    for (var i = 0; i < rows.length; i += batchSize) {
      final end = (i + batchSize < rows.length) ? i + batchSize : rows.length;
      final batch = rows.sublist(i, end);
      try {
        await _client.from(table).upsert(batch, onConflict: onConflict);
      } on PostgrestException catch (e) {
        debugPrint('[BDPM] Upsert error on $table: ${e.message}');
        rethrow;
      }
      onProgress?.call(end / total);
      // Small delay to avoid rate limits
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  String _safe(List<String> cols, int index) {
    if (index >= cols.length) return '';
    return cols[index].trim();
  }

  List<String> _splitList(String input) {
    if (input.isEmpty) return const [];
    return input
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.toLowerCase() != 'inconnu')
        .toList();
  }

  String? _parseFrDate(String input) {
    if (input.isEmpty) return null;
    final parts = input.split('/');
    if (parts.length != 3) return null;
    final dd = int.tryParse(parts[0]);
    final mm = int.tryParse(parts[1]);
    final yyyy = int.tryParse(parts[2]);
    if (dd == null || mm == null || yyyy == null) return null;
    try {
      final dt = DateTime.utc(yyyy, mm, dd);
      return dt.toIso8601String(); // PostgREST accepts ISO strings for date/time fields
    } catch (_) {
      return null;
    }
  }

  double? _parsePrice(String input) {
    if (input.isEmpty) return null;
    final normalized = input.replaceAll('€', '').replaceAll(' ', '').replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  bool? _toBool(String input) {
    final v = input.trim().toLowerCase();
    if (v == 'oui') return true;
    if (v == 'non') return false;
    return null;
  }
}
