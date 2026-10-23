import 'package:flutter/foundation.dart';
import 'package:medigo/supabase/supabase_config.dart';

class RolesService {
  // Hard-coded bootstrap admin id as requested
  static const String bootstrapAdminId = '8e3f313f-0c85-4427-bcd5-a8328c2eb6a8';

  static Future<bool> isAdmin() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return false;
    if (user.id == bootstrapAdminId) return true;
    try {
      final row = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) return false;
      return (row['role'] as String?) == 'admin';
    } catch (e) {
      debugPrint('RolesService.isAdmin failed: $e');
      return false;
    }
  }
}
