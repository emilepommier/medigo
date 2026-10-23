import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:medigo/supabase/supabase_config.dart';

class FamilyService {
  FamilyService._();

  static Future<String?> getCurrentFamilyId() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return null;
    try {
      // Try to get an existing membership
      final m = await SupabaseConfig.client
          .from('family_members')
          .select('family_id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (m != null) return m['family_id'] as String;
      // No default family anymore
      return null;
    } catch (e) {
      debugPrint('getCurrentFamilyId failed: $e');
      // Attempt a quick repair then retry once
      try {
        await healState();
        final m2 = await SupabaseConfig.client
            .from('family_members')
            .select('family_id')
            .eq('user_id', user.id)
            .maybeSingle();
        return m2?['family_id'] as String?;
      } catch (_) {
        return null;
      }
    }
  }

  static Future<Map<String, dynamic>?> getCurrentFamily() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return null;
    try {
      final famId = await getCurrentFamilyId();
      if (famId == null) return null;
      final row = await SupabaseConfig.client
          .from('families')
          .select('id, name, created_by, created_at')
          .eq('id', famId)
          .maybeSingle();
      return row;
    } catch (e) {
      debugPrint('getCurrentFamily failed: $e');
      return null;
    }
  }

  static Future<bool> renameFamily(String newName) async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return false;
    try {
      final famId = await getCurrentFamilyId();
      if (famId == null) return false;
      await SupabaseConfig.client
          .from('families')
          .update({'name': newName})
          .eq('id', famId);
      return true;
    } catch (e) {
      debugPrint('renameFamily failed: $e');
      return false;
    }
  }

  static String _randomCode({int length = 8}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// Explicitly create a family. Generates a single invite code for it.
  static Future<String?> createFamily(String name) async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return null;
    try {
      final code = _randomCode();
      final famRows = await SupabaseConfig.client
          .from('families')
          .insert({
            'name': name.isEmpty ? 'Ma famille' : name,
            'created_by': user.id,
            'invite_code': code,
          })
          .select('id');
      final familyId = famRows.first['id'] as String;
      await SupabaseConfig.client.from('family_members').insert({
        'family_id': familyId,
        'user_id': user.id,
        'role': 'owner',
      });
      // ensure single row in family_invites (compat)
      await SupabaseConfig.client.from('family_invites').upsert({
        'code': code,
        'family_id': familyId,
        'created_by': user.id,
      }, onConflict: 'family_id');
      return familyId;
    } catch (e) {
      debugPrint('createFamily failed: $e');
      return null;
    }
  }

  /// Join a family using its invite code.
  static Future<bool> redeemInvite(String code) async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return false;
    try {
      final res = await SupabaseConfig.client.rpc('rpc_join_family', params: {
        'p_code': code,
      });
      return res != null;
    } catch (e) {
      debugPrint('redeemInvite failed: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getMembers() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return [];
    try {
      final famId = await getCurrentFamilyId();
      if (famId == null) return [];
      final rows = await SupabaseConfig.client
          .from('family_members')
          .select('user_id, role')
          .eq('family_id', famId)
          .order('created_at');
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('getMembers failed: $e');
      return [];
    }
  }

  /// Return the single invite code for the current family (if any)
  static Future<String?> getInviteCode() async {
    try {
      final famId = await getCurrentFamilyId();
      if (famId == null) return null;
      final row = await SupabaseConfig.client
          .from('families')
          .select('invite_code')
          .eq('id', famId)
          .maybeSingle();
      return row?['invite_code'] as String?;
    } catch (e) {
      debugPrint('getInviteCode failed: $e');
      return null;
    }
  }

  /// Repairs broken membership state on the server (idempotent)
  static Future<void> healState() async {
    try {
      await SupabaseConfig.client.rpc('rpc_heal_family_state');
    } catch (e) {
      debugPrint('healState failed: $e');
    }
  }
}
