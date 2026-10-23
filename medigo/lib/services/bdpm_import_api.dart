import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:medigo/supabase/supabase_config.dart';

class BdpmImportApiResult {
  final bool success;
  final String message;
  final int? countDrugs;
  final int? countPresentations;
  final DateTime? finishedAt;

  BdpmImportApiResult({
    required this.success,
    required this.message,
    this.countDrugs,
    this.countPresentations,
    this.finishedAt,
  });
}

class BdpmImportApi {
  // Legacy combined function (if present)
  static const String _functionNameLegacy = 'bdpm_import';
  // New split functions
  static const String _fnCis = 'bdpm_import_cis';
  // IMPORTANT: function name with underscore between cis and cip
  static const String _fnCisCip = 'bdpm_import_cis_cip';

  /// Invoke the server-side importer (Edge Function) to avoid RLS issues.
  /// Requires that the Edge Function "bdpm_import" is deployed in Supabase.
  static Future<BdpmImportApiResult> runServerImportSplit() async {
    // 1) CIS (spécialités) en streaming
    final r1 = await runCisChunked();
    if (!r1.success) return r1;

    // 2) CIS_CIP en streaming, puis finalisation
    final r2 = await runCisCipChunked();
    if (!r2.success) return r2;

    return BdpmImportApiResult(
      success: true,
      message: 'Import serveur terminé (CIS + CIP).',
      countDrugs: r1.countDrugs,
      countPresentations: r2.countPresentations,
      finishedAt: r2.finishedAt ?? r1.finishedAt,
    );
  }

  // Fallback to legacy single function if needed
  static Future<BdpmImportApiResult> runServerImportLegacy(
      {String mode = 'full'}) async {
    return _invokeFunction(_functionNameLegacy, {'mode': mode});
  }

  static Future<BdpmImportApiResult> runCis() async {
    return runCisChunked();
  }

  static Future<BdpmImportApiResult> runCisCip() async {
    return runCisCipChunked();
  }

  /// Run the CIS import in multiple small byte-range chunks.
  static Future<BdpmImportApiResult> runCisChunked(
      {int maxBytesPerCall = 120000}) async {
    int processedTotal = 0;
    int byteOffset = 0;
    String carry = '';

    for (int i = 0; i < 100000; i++) {
      final raw = await _invokeRaw(_fnCis, {
        'byte_offset': byteOffset,
        'max_bytes': maxBytesPerCall,
        'carry': carry,
      });

      if (raw['ok'] != true) {
        final msg =
            raw['error']?.toString() ?? 'Erreur inconnue pendant l\'import CIS';
        return BdpmImportApiResult(success: false, message: msg);
      }

      final processed = (raw['processed'] is int) ? raw['processed'] as int : 0;
      processedTotal += processed;
      final next = raw['next_byte_offset'];
      final nextCarry = raw['carry']?.toString() ?? '';
      final isPartial = raw['is_partial'] == true;

      if (next is int) {
        byteOffset = next;
      } else {
        break;
      }
      carry = nextCarry;
      // Quand le serveur ne renvoie plus 206 (is_partial=false) et qu'on n'a plus de carry, on s'arrête
      if (!isPartial && (nextCarry.isEmpty)) break;
      // Stop si rien n'a été traité, pour éviter boucle infinie
      if (processed == 0) break;
    }

    // Finalise et récupère le nombre exact
    final fin = await _invokeRaw(_fnCis, {'finalize': true});
    if (fin['ok'] == true) {
      return BdpmImportApiResult(
        success: true,
        message: 'Import CIS terminé',
        countDrugs:
            (fin['count_drugs'] is int) ? fin['count_drugs'] as int : null,
        finishedAt: DateTime.now(),
      );
    }
    return BdpmImportApiResult(
      success: false,
      message: fin['error']?.toString() ?? 'Finalisation CIS échouée',
    );
  }

  /// Run the CIP import in multiple small byte-range chunks.
  static Future<BdpmImportApiResult> runCisCipChunked(
      {int maxBytesPerCall = 16000}) async {
    int processedTotal = 0;
    int byteOffset = 0;
    String carry = '';

    for (int i = 0; i < 100000; i++) {
      final raw = await _invokeRaw(_fnCisCip, {
        'byte_offset': byteOffset,
        'max_bytes': maxBytesPerCall,
        'carry': carry,
      });

      if (raw['ok'] != true) {
        final msg =
            raw['error']?.toString() ?? 'Erreur inconnue pendant l\'import CIP';
        return BdpmImportApiResult(success: false, message: msg);
      }

      final processed = (raw['processed'] is int) ? raw['processed'] as int : 0;
      processedTotal += processed;
      final next = raw['next_byte_offset'];
      final nextCarry = raw['carry']?.toString() ?? '';
      final isPartial = raw['is_partial'] == true;

      if (next is int) {
        byteOffset = next;
      } else {
        break;
      }
      carry = nextCarry;
      if (!isPartial && (nextCarry.isEmpty)) break;
      if (processed == 0) break;
    }

    // Finalize: compute exact count and update metadata
    final fin = await _invokeRaw(_fnCisCip, {'finalize': true});
    if (fin['ok'] == true) {
      return BdpmImportApiResult(
        success: true,
        message: 'Import CIP terminé',
        countPresentations: (fin['count_presentations'] is int)
            ? fin['count_presentations'] as int
            : null,
        finishedAt: DateTime.now(),
      );
    }
    return BdpmImportApiResult(
      success: false,
      message: fin['error']?.toString() ?? 'Finalisation CIP échouée',
      countPresentations: null,
    );
  }

  static Future<BdpmImportApiResult> _invokeFunction(
      String name, Map<String, dynamic> body) async {
    try {
      final data = await _invokeRaw(name, body);
      if (data['ok'] == true) {
        return BdpmImportApiResult(
          success: true,
          message: data['message']?.toString() ?? 'OK',
          countDrugs:
              (data['count_drugs'] is int) ? data['count_drugs'] as int : null,
          countPresentations: (data['count_presentations'] is int)
              ? data['count_presentations'] as int
              : null,
          finishedAt: data['finished_at'] != null
              ? DateTime.tryParse(data['finished_at'] as String)
              : null,
        );
      }
      return BdpmImportApiResult(
        success: false,
        message: data['error']?.toString() ??
            'Erreur inconnue lors de l\'appel fonction "$name"',
      );
    } catch (e) {
      debugPrint('[BDPM] Edge Function exception ($name): $e');
      return BdpmImportApiResult(success: false, message: e.toString());
    }
  }

  static Future<Map<String, dynamic>> _invokeRaw(
      String name, Map<String, dynamic> body) async {
    final functions = SupabaseConfig.client.functions;
    final res = await functions.invoke(
      name,
      body: jsonEncode(body),
      headers: const {
        'Content-Type': 'application/json',
      },
    );
    dynamic data = res.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        data = {
          'ok': false,
          'error': 'Réponse non JSON de la fonction "$name"'
        };
      }
    }
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'ok': false, 'error': 'Réponse invalide de la fonction "$name"'};
  }
}
