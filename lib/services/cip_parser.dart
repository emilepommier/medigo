import 'package:flutter/foundation.dart';

class CipParseResult {
  final String? cip13;
  final String? cip7;
  final String raw;
  final String? source; // e.g., 'gs1_ai_01', 'digits_in_text', 'ean13'

  const CipParseResult({required this.raw, this.cip13, this.cip7, this.source});

  bool get hasCip13 => cip13 != null && cip13!.length == 13;
}

class CipParser {
  CipParser._();

  static bool _isValidEan13(String digits) {
    if (digits.length != 13) return false;
    for (int i = 0; i < digits.length; i++) {
      final c = digits.codeUnitAt(i);
      if (c < 48 || c > 57) return false; // not a digit
    }
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final d = digits.codeUnitAt(i) - 48;
      sum += (i % 2 == 0) ? d : d * 3;
    }
    final check = (10 - (sum % 10)) % 10;
    return check == (digits.codeUnitAt(12) - 48);
  }

  // Extract first valid CIP13 from text. Falls back to CIP7 if found.
  static CipParseResult parse(String? input) {
    final raw = input?.trim() ?? '';
    if (raw.isEmpty) {
      return const CipParseResult(raw: '', cip13: null, cip7: null, source: null);
    }

    // Normalize: replace ASCII GS (29) with pipe to split
    final normalized = raw.replaceAll(String.fromCharCode(29), '|');

    // 1) GS1 AI (01) – 14-digit GTIN that may contain a leading 0 before CIP13
    // Pattern: 01(14 digits)
    final ai01 = RegExp(r'01(\d{14})');
    final m01 = ai01.firstMatch(normalized);
    if (m01 != null) {
      final gtin14 = m01.group(1)!; // length 14
      // Case A: leading 0 + CIP13 starting with 34009 ...
      if (gtin14.startsWith('0') && gtin14.length == 14) {
        final candidate = gtin14.substring(1); // 13 digits
        if (candidate.startsWith('34009') && _isValidEan13(candidate)) {
          return CipParseResult(raw: raw, cip13: candidate, source: 'gs1_ai_01');
        }
      }
      // Case B: Sometimes GTIN itself may be a 14-digit starting with 034009..., if checksum oddly placed
      // Try also to find any 13-digit sliding window starting index 0 or 1 that validates
      for (int i = 0; i <= 1; i++) {
        final window = gtin14.substring(i, i + 13);
        if (window.startsWith('34009') && _isValidEan13(window)) {
          return CipParseResult(raw: raw, cip13: window, source: 'gs1_ai_01_window');
        }
      }
    }

    // 2) Direct 13-digit CIP beginning with 34009 and valid checksum
    final r13 = RegExp(r'(?:^|\D)(34009\d{8})(?!\d)');
    final m13 = r13.firstMatch(normalized);
    if (m13 != null) {
      final candidate = m13.group(1)!;
      if (_isValidEan13(candidate)) {
        return CipParseResult(raw: raw, cip13: candidate, source: 'digits_in_text');
      }
    }

    // 3) Try to detect any 13-digit number with valid EAN-13 and starting 34009 even if surrounded by others
    final any13 = RegExp(r'(\d{13})');
    for (final m in any13.allMatches(normalized)) {
      final candidate = m.group(1)!;
      if (candidate.startsWith('34009') && _isValidEan13(candidate)) {
        return CipParseResult(raw: raw, cip13: candidate, source: 'any_13');
      }
    }

    // 4) As a last resort, try to find a CIP7 substring (7 digits) often included in labels
    final r7 = RegExp(r'(?:^|\D)(\d{7})(?!\d)');
    final m7 = r7.firstMatch(normalized);
    if (m7 != null) {
      return CipParseResult(raw: raw, cip13: null, cip7: m7.group(1), source: 'cip7');
    }

    debugPrint('CIP parse failed for: $raw');
    return CipParseResult(raw: raw, cip13: null, cip7: null, source: 'unparsed');
  }
}
