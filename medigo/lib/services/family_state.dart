import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:medigo/services/family_service.dart';
import 'package:medigo/supabase/supabase_config.dart';

/// Holds current family-related data for the signed-in user and keeps it fresh.
/// Preloads at app start to avoid visible loading on first visit to Settings.
class FamilyState extends ChangeNotifier {
  String? _familyId;
  Map<String, dynamic>? _family; // contains id, name, created_by, created_at
  List<Map<String, dynamic>> _members = const [];
  String? _inviteCode;
  bool _loading = false;

  StreamSubscription? _authSub;

  FamilyState() {
    // Keep in sync with auth changes
    _authSub = SupabaseConfig.auth.onAuthStateChange.listen((event) {
      try {
        final user = SupabaseConfig.auth.currentUser;
        if (user == null) {
          _clear();
        } else {
          // Trigger refresh on login/token refresh
          preload();
        }
      } catch (e) {
        debugPrint('FamilyState auth listener error: $e');
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  bool get isLoading => _loading;
  String? get familyId => _familyId;
  Map<String, dynamic>? get family => _family;
  String? get familyName => (_family?['name'] as String?)?.trim();
  List<Map<String, dynamic>> get members => _members;
  String? get inviteCode => _inviteCode;

  void _clear() {
    _familyId = null;
    _family = null;
    _members = const [];
    _inviteCode = null;
    notifyListeners();
  }

  /// Preload family data. Safe to call multiple times; runs in background.
  Future<void> preload() async {
    // If not authenticated, just clear state
    if (SupabaseConfig.auth.currentUser == null) {
      _clear();
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      // Load in parallel to minimize latency
      final fid = await FamilyService.getCurrentFamilyId();
      if (fid == null) {
        _familyId = null;
        _family = null;
        _members = const [];
        _inviteCode = null;
        return;
      }
      final results = await Future.wait([
        FamilyService.getCurrentFamily(),
        FamilyService.getMembers(),
        FamilyService.getInviteCode(),
      ]);
      _familyId = fid;
      _family = results[0] as Map<String, dynamic>?;
      _members = (results[1] as List<Map<String, dynamic>>);
      _inviteCode = results[2] as String?;
    } catch (e) {
      debugPrint('FamilyState preload error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Explicit refresh (e.g., after rename, create, or join).
  Future<void> refresh() => preload();
}
