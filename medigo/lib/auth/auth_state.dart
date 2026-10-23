import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:medigo/supabase/supabase_config.dart';

class AuthStateNotifier extends ChangeNotifier {
  AuthStateNotifier() {
    // Listen to auth state changes and notify router
    _sub = SupabaseConfig.auth.onAuthStateChange.listen((event) {
      notifyListeners();
    });
  }

  late final StreamSubscription _sub;

  bool get isLoggedIn => SupabaseConfig.auth.currentUser != null;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
