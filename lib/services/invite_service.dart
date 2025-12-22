import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:medigo/supabase/supabase_config.dart';

class InviteService {
  InviteService._();

  static String _randomCode({int length = 8}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  // Admin: create a signup invite for an email (optional) and return the code
  static Future<String?> createSignupInvite({String? email, Duration ttl = const Duration(days: 7)}) async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return null;
    try {
      final code = _randomCode();
      final expiresAt = DateTime.now().add(ttl).toUtc().toIso8601String();
      final rows = await SupabaseConfig.client.from('signup_invites').insert({
        'code': code,
        'email': email,
        'created_by': user.id,
        'expires_at': expiresAt,
        'role': 'user',
      }).select('code');
      return rows.first['code'] as String;
    } catch (e) {
      debugPrint('createSignupInvite failed: $e');
      return null;
    }
  }

  // Validate an invite code before signup (anon allowed by RLS policy)
  static Future<Map<String, dynamic>?> validateInvite(String code, {String? email}) async {
    try {
      final row = await SupabaseConfig.client
          .from('signup_invites')
          .select('code,email,expires_at,used_by,role')
          .eq('code', code)
          .maybeSingle();
      if (row == null) return null;
      if (row['used_by'] != null) return null;
      final exp = DateTime.tryParse(row['expires_at'] as String? ?? '');
      if (exp == null || DateTime.now().toUtc().isAfter(exp)) return null;
      if ((row['email'] as String?) != null && email != null) {
        if ((row['email'] as String).toLowerCase().trim() != email.toLowerCase().trim()) {
          return null;
        }
      }
      return row as Map<String, dynamic>;
    } catch (e) {
      debugPrint('validateInvite failed: $e');
      return null;
    }
  }

  // After successful signup, mark invite as used
  static Future<bool> markInviteUsed(String code) async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return false;
    try {
      await SupabaseConfig.client
          .from('signup_invites')
          .update({
            'used_by': user.id,
            'used_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('code', code);
      return true;
    } catch (e) {
      debugPrint('markInviteUsed failed: $e');
      return false;
    }
  }
}
