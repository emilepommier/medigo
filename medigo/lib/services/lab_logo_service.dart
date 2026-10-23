import 'package:flutter/foundation.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/services/roles.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages laboratory logo images stored in Supabase Storage.
/// Logos are GLOBAL (shared across all users) and keyed by the "titulaire" name.
///
/// Path scheme (deterministic):
///   bucket: lab-logos
///   object: titulaires/<slug>/logo.jpg
///
/// Slug generation ignores any parenthetical content and keeps alphanumerics
/// with hyphens for stability (lowercase). Parentheses are removed entirely.
class LabLogoService {
  LabLogoService._();

  static const String bucket = 'lab-logos';
  static bool _bucketMissingWarned = false;
  static bool _objectMissingLogged = false;

  /// Build a stable object path for a titulaire name.
  static String buildLogoPath(String titulaire) {
    final slug = _slugify(titulaire);
    return 'titulaires/$slug/logo.jpg';
  }

  /// Download the logo as bytes. Returns null if not found or on error.
  static Future<Uint8List?> getLogoBytes(String titulaire) async {
    try {
      final path = buildLogoPath(titulaire);
      final bytes = await SupabaseConfig.client.storage.from(bucket).download(path);
      return bytes;
    } catch (e) {
      debugPrint('LabLogoService.getLogoBytes failed: $e');
      final msg = e.toString().toLowerCase();
      if (!_bucketMissingWarned && _isBucketMissing(msg)) {
        _bucketMissingWarned = true;
        debugPrint('Hint: Create a Supabase Storage bucket named "$bucket" (public read), then grant write/delete only to admins.');
      } else if (!_objectMissingLogged && _isObjectMissing(msg)) {
        // Object not found is expected when no logo exists yet. Log once to avoid noise.
        _objectMissingLogged = true;
        debugPrint('LabLogoService: no logo yet for "$titulaire". This is normal until an admin uploads one.');
      }
      return null;
    }
  }

  /// Uploads the provided (already compressed) bytes as the logo for titulaire.
  /// Upserts the object. Returns the storage path on success, null otherwise.
  static Future<String?> uploadLogo({required String titulaire, required Uint8List bytes, String contentType = 'image/jpeg'}) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      // This mirrors the app-side admin check to help debug RLS policy mismatches
      final appAdmin = await RolesService.isAdmin();
      debugPrint('LabLogoService.uploadLogo: uid=$uid appIsAdmin=$appAdmin');
      final path = buildLogoPath(titulaire);
      await SupabaseConfig.client.storage.from(bucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: contentType,
          upsert: true,
          // Ensure CDNs and browsers don't serve stale copies after updates
          cacheControl: 'no-store, no-cache, must-revalidate, max-age=0',
        ),
      );
      return path;
    } catch (e) {
      debugPrint('LabLogoService.uploadLogo failed: $e');
      final msg = e.toString().toLowerCase();
      if (!_bucketMissingWarned && _isBucketMissing(msg)) {
        _bucketMissingWarned = true;
        debugPrint('Hint: Create a Supabase Storage bucket named "$bucket" (public read), then grant write/delete only to admins.');
      } else if (msg.contains('row-level security policy') || msg.contains('statuscode": "403') || msg.contains('statuscode: 403')) {
        // Give a precise hint for Storage RLS policy setup
        debugPrint("Hint: Storage RLS is denying INSERT. Ensure a policy exists on storage.objects for bucket_id = \"$bucket\" that allows INSERT to authenticated users WHEN the current user is admin.");
        debugPrint("       Example check: bucket_id = \"$bucket\" AND (exists (select 1 from public.users u where u.id = auth.uid() and u.role = 'admin') OR auth.uid() = '8e3f313f-0c85-4427-bcd5-a8328c2eb6a8').");
      }
      return null;
    }
  }

  /// Deletes the logo object for the titulaire if it exists.
  static Future<void> deleteLogo(String titulaire) async {
    try {
      final path = buildLogoPath(titulaire);
      await SupabaseConfig.client.storage.from(bucket).remove([path]);
    } catch (e) {
      debugPrint('LabLogoService.deleteLogo failed: $e');
    }
  }

  /// Slugify rules:
  /// - Remove parentheses and content within them
  /// - Replace non-alphanumeric with hyphens
  /// - Collapse multiple hyphens; trim leading/trailing hyphens
  /// - Lowercase
  static String _slugify(String input) {
    var s = input.trim();
    s = s.replaceAll(RegExp(r"\([^)]*\)"), ''); // remove ( ... )
    // Keep letters (incl. accents) and digits; others become hyphens
    s = s.replaceAll(RegExp(r"[^A-Za-z0-9À-ÖØ-öø-ÿ]+"), '-');
    s = s.replaceAll(RegExp(r"-+"), '-');
    s = s.replaceAll(RegExp(r"^-|-"), '');
    s = s.toLowerCase();
    if (s.isEmpty) return 'unknown';
    return s;
  }

  static bool _isBucketMissing(String msg) {
    // Supabase may report either plain text or JSON with message "Bucket not found"
    return msg.contains('bucket not found');
  }

  static bool _isObjectMissing(String msg) {
    // e.g. {"statusCode":"404","error":"not_found","message":"Object not found"}
    return msg.contains('object not found');
  }
}
