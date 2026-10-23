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

  /// Extracts a display title and subtitle from a raw denomination string.
  ///
  /// Heuristics:
  /// - Supports a single denomination or multiple joined by " + " (e.g.,
  ///   "TOLVAPTAN BIOGARAN 30 mg, comprimé + TOLVAPTAN BIOGARAN 60 mg, comprimé").
  /// - For multiple variants: Title is the longest common uppercase word prefix
  ///   before the first dosage across all parts (e.g., "TOLVAPTAN BIOGARAN").
  ///   Subtitle is the unique list of strengths joined with " et " (e.g.,
  ///   "30 mg et 60 mg").
  /// - For a single variant: Title is the first uppercase word before the first
  ///   dosage (e.g., "AMOXICILLINE"). Subtitle is the first detected strength
  ///   (e.g., "1 g"). If no strength is found, fallback to text after comma or
  ///   the remaining text after the title.
  ///
  /// Returns a record (title, subtitle).
  static (String, String) splitTitleSubtitle(String? denomination) {
    try {
      final raw = (denomination ?? '').trim();
      if (raw.isEmpty) return ('', '');

      // Split potential multiple variants: we consider ` + ` as a separator.
      final parts = raw.split(RegExp(r'\s\+\s'));

      // Regex to capture a strength like:
      //  - "30 mg", "1 g", "500 µg", "5 mg/mL", "10 000 UI/ml", "1%", "2,5 mg", "1000 mg", "200 U.CEIP/ml" etc.
      // Supports:
      //  - Continuous digits (e.g., 1000)
      //  - Spaced thousands (e.g., 10 000)
      //  - Comma/point decimals (e.g., 1,2 or 1.2)
      //  - Units including: %, mg, g, µg/mcg/ug, mL/ml/L, UI/IU, and U.<ACRONYM> (e.g., U.CEIP)
      //  - Optional divisor with either a number+volume (e.g., /0,4 ml) or just a volume unit (e.g., /ml)
      final strengthRx = RegExp(
        r'(\d{1,3}(?:[ \u00A0]?\d{3})*(?:[\.,]\d+)?|\d+(?:[\.,]\d+)?)\s*'
        r'(?:%|mg|g|µg|mcg|ug|mL|ml|L|l|UI|IU|U(?:\.[A-Z]{1,6})+)' // numerator unit (includes U.CEIP style)
        r'(?:\s*/\s*(?:' // optional divisor
        r'(?:\d{1,3}(?:[ \u00A0]?\d{3})*(?:[\.,]\d+)?|\d+(?:[\.,]\d+)?)\s*(?:mL|ml|L|l)?' // number then optional volume
        r'|(?:mL|ml|L|l)' // or just a volume unit like /mL
        r'))?',
        caseSensitive: false,
      );

      // Extract helper per part: prefix words before strength, and the first strength.
      List<String> prefixWordsPerPart = [];
      List<String> strengths = [];

      for (final partRaw in parts) {
        final part = partRaw.trim();
        // Consider text up to the first comma that is NOT a decimal separator.
        // We must not split inside numbers like "0,25". We look for a comma
        // whose previous and next non-space chars are NOT both digits.
        String beforeComma;
        {
          int splitIdx = -1;
          for (int i = 0; i < part.length; i++) {
            if (part[i] != ',') continue;
            // Find previous non-space and next non-space chars
            int j = i - 1;
            while (j >= 0 && part[j] == ' ') {
              j--;
            }
            int k = i + 1;
            while (k < part.length && part[k] == ' ') {
              k++;
            }
            final prev = j >= 0 ? part[j] : null;
            final next = k < part.length ? part[k] : null;
            final isPrevDigit = prev != null && RegExp(r'\d').hasMatch(prev);
            final isNextDigit = next != null && RegExp(r'\d').hasMatch(next);
            if (!(isPrevDigit && isNextDigit)) {
              splitIdx = i;
              break;
            }
          }
          beforeComma =
              splitIdx >= 0 ? part.substring(0, splitIdx).trim() : part.trim();
        }

        // Find first strength occurrence.
        final m = strengthRx.firstMatch(beforeComma);
        String titlePrefix;
        String? strength;
        if (m != null) {
          final idx = m.start;
          // Trim trailing brackets if the strength starts inside parentheses, e.g., "... (0,1 mg/0,4 ml)"
          var tp = beforeComma.substring(0, idx).trimRight();
          tp = tp.replaceFirst(RegExp(r'[\(\[\{]\s*$'), '').trimRight();
          titlePrefix = tp;
          strength = m.group(0)?.trim();
        } else {
          titlePrefix = beforeComma;
          strength = null;
        }

        // Split prefix into uppercase-like words (keep original casing but these are typically caps).
        final words = titlePrefix
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
        prefixWordsPerPart.add(words.join(' ').trim());
        if (strength != null && strength.isNotEmpty) strengths.add(strength);
      }

      String title = '';
      String subtitle = '';

      if (parts.length > 1) {
        // Compute the longest common prefix by words among all parts.
        List<String> commonWords =
            prefixWordsPerPart.first.split(RegExp(r'\s+')).toList();
        for (int i = 1; i < prefixWordsPerPart.length; i++) {
          final words = prefixWordsPerPart[i].split(RegExp(r'\s+')).toList();
          final minLen = commonWords.length < words.length
              ? commonWords.length
              : words.length;
          int j = 0;
          while (j < minLen && commonWords[j] == words[j]) {
            j++;
          }
          commonWords = commonWords.sublist(0, j);
          if (commonWords.isEmpty) break;
        }
        title = commonWords.isNotEmpty
            ? commonWords.join(' ')
            : prefixWordsPerPart.first.split(' ').first;

        // Build subtitle as unique strengths joined with " et ". Keep insertion order.
        final seen = <String>{};
        final uniqueStrengths = <String>[];
        for (final s in strengths) {
          if (s.isEmpty) continue;
          if (seen.add(s)) uniqueStrengths.add(s);
        }
        subtitle = uniqueStrengths.join(' et ');
      } else {
        // Single variant:
        //  - Title: keep the leading ONE or TWO uppercase-like tokens before the strength
        //    (e.g., "ZYMAD" or "TIXOCORTOL TEVA"). This matches brand + lab when present.
        //    EXCEPTION: if the prefix contains a label phrase like "POUR MILLE", keep the full prefix.
        //  - Subtitle: the first detected strength. Do NOT fallback to text after comma.
        final onlyPrefix = prefixWordsPerPart.isNotEmpty
            ? prefixWordsPerPart.first
            : raw.split(',').first;
        final words = onlyPrefix
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
        // Detect uppercase-like tokens (allow hyphens and digits).
        final isUpper = RegExp(r'^[A-ZÀ-Ÿ0-9\-]+$');
        final upperTokens = <String>[];
        if (RegExp(r'\bPOUR\s+MILLE\b', caseSensitive: false)
                .hasMatch(onlyPrefix) ||
            RegExp(r'\bPOUR\s+CENT\b', caseSensitive: false)
                .hasMatch(onlyPrefix)) {
          title = onlyPrefix.trim();
        } else {
          for (final w in words) {
            if (isUpper.hasMatch(w)) {
              upperTokens.add(w);
            } else {
              break; // stop at the first non-uppercase token
            }
          }
          if (upperTokens.isEmpty) {
            title = words.isNotEmpty ? words.first : onlyPrefix;
          } else {
            // Keep up to two tokens for readability (e.g., "TIXOCORTOL TEVA").
            title = upperTokens.take(2).join(' ');
          }
        }

        // Strength: if found use it; otherwise leave subtitle empty per product request.
        if (strengths.isNotEmpty && strengths.first.isNotEmpty) {
          subtitle = strengths.first;
        } else {
          subtitle = '';
        }
      }

      return (title.trim(), subtitle.trim());
    } catch (e) {
      debugPrint('splitTitleSubtitle failed: $e');
      return (denomination ?? '', '');
    }
  }

  /// Convert a title to Title Case (Camel Case-like) for display.
  /// - Preserves hyphenated parts and apostrophes (e.g., "L'AMOXICILLINE" -> "L'Amoxicilline").
  /// - Only downcases tokens that are fully uppercase to avoid ruining proper casing.
  static String toTitleCase(String input) {
    if (input.trim().isEmpty) return input;
    String cap(String s) => s.isEmpty
        ? s
        : s[0].toUpperCase() +
            (s.length > 1 ? s.substring(1).toLowerCase() : '');
    String capToken(String token) {
      // Handle apostrophes inside token: split and cap each side if needed
      final apostropheParts = token.split("'");
      final processedApostrophe = apostropheParts.map((part) {
        // Handle hyphenated subparts
        final hyphenParts = part.split('-');
        final processedHyphen = hyphenParts.map((hp) {
          final isAllCaps = RegExp(r'^[A-ZÀ-Ÿ0-9]+$').hasMatch(hp);
          return isAllCaps ? cap(hp) : (hp.isEmpty ? hp : cap(hp));
        }).join('-');
        return processedHyphen;
      }).join("'");
      return processedApostrophe;
    }

    final tokens = input.split(RegExp(r'\s+'));
    final processed = tokens.map(capToken).join(' ');
    return processed.trim();
  }
}
