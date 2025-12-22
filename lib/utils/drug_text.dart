import 'package:flutter/foundation.dart';

/// Utility helpers for drug-related text normalization.
class DrugTextUtils {
  DrugTextUtils._();

  /// Remove duplicated forme from denomination when it follows a comma.
  /// Example: denomination="INOFER, comprimé pelliculé" and forme="comprimé pelliculé"
  /// returns "INOFER".
  static String sanitizeDenomination(String? denomination, String? forme) {
    try {
      final denom = (denomination ?? '').trim();
      final form = (forme ?? '').trim();
      if (denom.isEmpty || form.isEmpty) return denom;

      // If denomination ends with ", <forme>" (case-insensitive, trimmed), strip it.
      final lowerDenom = denom.toLowerCase();
      final lowerForm = form.toLowerCase();
      final suffix = ', $lowerForm';
      if (lowerDenom.endsWith(suffix)) {
        final result = denom.substring(0, denom.length - suffix.length).trim();
        return result;
      }
      return denom;
    } catch (e) {
      debugPrint('sanitizeDenomination failed: $e');
      return denomination ?? '';
    }
  }
}
