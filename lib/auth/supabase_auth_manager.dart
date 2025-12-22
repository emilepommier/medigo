import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:medigo/auth/auth_manager.dart';
import 'package:medigo/models/user.dart';
import 'package:medigo/supabase/supabase_config.dart';
import 'package:medigo/services/family_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class SupabaseAuthManager extends AuthManager with EmailSignInManager {
  @override
  Future<User?> signInWithEmail(
    BuildContext context,
    String email,
    String password,
  ) async {
    try {
      final response = await SupabaseConfig.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        // Attempt to heal any broken family membership state on login
        await FamilyService.healState();
        return await _getUserProfile(response.user!.id);
      }
      return null;
    } on supabase.AuthException catch (e) {
      debugPrint('Sign in error: ${e.message}');
      if (context.mounted) {
        _showError(context, e.message);
      }
      return null;
    } catch (e) {
      debugPrint('Sign in error: $e');
      if (context.mounted) {
        _showError(context, 'Failed to sign in. Please try again.');
      }
      return null;
    }
  }

  @override
  Future<User?> createAccountWithEmail(
    BuildContext context,
    String email,
    String password,
  ) async {
    try {
      final response = await SupabaseConfig.auth.signUp(
        email: email,
        password: password,
        // Ensure email confirmation opens the app via custom scheme
        emailRedirectTo: 'io.supabase.flutter://login-callback',
      );

      if (response.user != null) {
        // Create user profile in users table
        await SupabaseConfig.client.from('users').insert({
          'id': response.user!.id,
          'email': email,
          'full_name': null,
          'role': 'user',
        });
        // Heal state just in case (idempotent)
        await FamilyService.healState();

        return User(
          id: response.user!.id,
          email: email,
          fullName: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }
      return null;
    } on supabase.AuthException catch (e) {
      debugPrint('Sign up error: ${e.message}');
      if (context.mounted) {
        _showError(context, e.message);
      }
      return null;
    } catch (e) {
      debugPrint('Sign up error: $e');
      if (context.mounted) {
        _showError(context, 'Failed to create account. Please try again.');
      }
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await SupabaseConfig.auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteUser(BuildContext context) async {
    try {
      final userId = SupabaseConfig.auth.currentUser?.id;
      if (userId != null) {
        // Delete user profile (cascade will handle auth.users)
        await SupabaseConfig.client.from('users').delete().eq('id', userId);
      }
    } catch (e) {
      debugPrint('Delete user error: $e');
      if (context.mounted) {
        _showError(context, 'Failed to delete account. Please try again.');
      }
      rethrow;
    }
  }

  @override
  Future<void> updateEmail({
    required String email,
    required BuildContext context,
  }) async {
    try {
      await SupabaseConfig.auth.updateUser(supabase.UserAttributes(email: email));
      
      // Update email in users table
      final userId = SupabaseConfig.auth.currentUser?.id;
      if (userId != null) {
        await SupabaseConfig.client.from('users').update({'email': email}).eq('id', userId);
      }
    } on supabase.AuthException catch (e) {
      debugPrint('Update email error: ${e.message}');
      if (context.mounted) {
        _showError(context, e.message);
      }
      rethrow;
    } catch (e) {
      debugPrint('Update email error: $e');
      if (context.mounted) {
        _showError(context, 'Failed to update email. Please try again.');
      }
      rethrow;
    }
  }

  @override
  Future<void> resetPassword({
    required String email,
    required BuildContext context,
  }) async {
    try {
      await SupabaseConfig.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.flutter://login-callback',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent')),
        );
      }
    } on supabase.AuthException catch (e) {
      debugPrint('Reset password error: ${e.message}');
      if (context.mounted) {
        _showError(context, e.message);
      }
      rethrow;
    } catch (e) {
      debugPrint('Reset password error: $e');
      if (context.mounted) {
        _showError(context, 'Failed to send password reset email. Please try again.');
      }
      rethrow;
    }
  }

  Future<User?> _getUserProfile(String userId) async {
    try {
      final data = await SupabaseConfig.client
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data != null) {
        return User.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Get user profile error: $e');
      return null;
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Get current authenticated user
  static Future<User?> getCurrentUser() async {
    final authUser = SupabaseConfig.auth.currentUser;
    if (authUser == null) return null;

    try {
      final data = await SupabaseConfig.client
          .from('users')
          .select()
          .eq('id', authUser.id)
          .maybeSingle();

      if (data != null) {
        return User.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Get current user error: $e');
      return null;
    }
  }

  // Check if user is authenticated
  static bool isAuthenticated() => SupabaseConfig.auth.currentUser != null;
}
