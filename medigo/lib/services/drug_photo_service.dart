import 'package:flutter/foundation.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/services/family_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles upload/delete of drug box photos to Supabase Storage and creates
/// signed URLs for secure access. Photos are scoped by family and cip key.
class DrugPhotoService {
  DrugPhotoService._();

  static const String bucket = 'drug-photos';

  // In-memory signed URL cache with simple TTL
  static final Map<String, _SignedUrlCache> _cache = {};

  // New: in-memory bytes Future cache keyed by cipKey to avoid duplicate downloads per build
  static final Map<String, Future<Uint8List?>> _bytesFutureCache = {};

  /// Explicitly invalidate any cached image bytes for a cipKey
  static void invalidateCache(String cipKey) {
    try {
      _bytesFutureCache.remove(cipKey);
    } catch (_) {}
  }

  /// Returns the deterministic storage path for a cover photo.
  /// cipKey is either cip13 or a customKey (e.g., 'custom:...').
  static Future<String?> buildCoverPath(String cipKey) async {
    try {
      final fam = await FamilyService.getCurrentFamilyId();
      if (fam == null) return null;
      final safe = cipKey.replaceAll('/', '_');
      return 'families/$fam/$safe/cover.jpg';
    } catch (e) {
      debugPrint('DrugPhotoService.buildCoverPath failed: $e');
      return null;
    }
  }

  /// Returns the currently stored cover path for cipKey if any (from DB).
  static Future<String?> getCoverPath(String cipKey) async {
    try {
      final familyId = await FamilyService.getCurrentFamilyId();
      if (familyId == null) return null;
      if (cipKey.startsWith('custom:')) {
        final row = await SupabaseConfig.client
            .from('custom_items')
            .select('photo_url')
            .eq('family_id', familyId)
            .eq('custom_key', cipKey)
            .maybeSingle();
        final p = (row)?['photo_url'] as String?;
        return (p != null && p.isNotEmpty) ? p : null;
      }
      final rows = await SupabaseConfig.client
          .from('pharmacy_item_entries')
          .select('photo_url')
          .eq('family_id', familyId)
          .eq('cip13', cipKey)
          .not('photo_url', 'is', null)
          .order('added_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        final p = (rows.first)['photo_url'] as String?;
        return (p != null && p.isNotEmpty) ? p : null;
      }
      return null;
    } catch (e) {
      debugPrint('DrugPhotoService.getCoverPath failed: $e');
      return null;
    }
  }

  /// Download cover bytes for display (auth protected).
  static Future<Uint8List?> getCoverBytes(String cipKey) async {
    // Return the same in-flight/completed future to all callers
    final cached = _bytesFutureCache[cipKey];
    if (cached != null) return cached;
    final future = () async {
      try {
        final path = await getCoverPath(cipKey);
        if (path == null) return null;
        final bytes = await SupabaseConfig.client.storage.from(bucket).download(path);
        return bytes;
      } catch (e) {
        debugPrint('DrugPhotoService.getCoverBytes failed: $e');
        return null;
      }
    }();
    _bytesFutureCache[cipKey] = future;
    return future;
  }

  /// Uploads the provided bytes as the family-scoped cover for the cipKey.
  /// Returns the storage object path if successful.
  static Future<String?> uploadCover({required String cipKey, required Uint8List bytes, String contentType = 'image/jpeg'}) async {
    try {
      final path = await buildCoverPath(cipKey);
      if (path == null) return null;
      await SupabaseConfig.client.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: true));
      // Invalidate cache for this path
      _cache.remove(path);
      return path;
    } catch (e) {
      debugPrint('DrugPhotoService.uploadCover failed: $e');
      return null;
    }
  }

  /// Deletes the deterministic cover object for the cipKey, if it exists.
  static Future<void> deleteCoverByCipKey(String cipKey) async {
    try {
      final path = await buildCoverPath(cipKey);
      if (path == null) return;
      await deleteObject(path);
      invalidateCache(cipKey);
    } catch (e) {
      debugPrint('DrugPhotoService.deleteCoverByCipKey failed: $e');
    }
  }

  /// Deletes the specific object path.
  static Future<void> deleteObject(String path) async {
    try {
      await SupabaseConfig.client.storage.from(bucket).remove([path]);
      _cache.remove(path);
    } catch (e) {
      debugPrint('DrugPhotoService.deleteObject failed: $e');
    }
  }

  // Signed URL support is intentionally omitted for now to avoid version mismatches.
}

class _SignedUrlCache {
  final String url;
  final DateTime expiresAt;
  _SignedUrlCache({required this.url, required this.expiresAt});
}
