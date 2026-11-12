import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repo.dart';
import 'notifications.dart';
import 'scroll_guard.dart';
import 'widget_sync.dart';

/// Why deleting stopped, in words for the person.
class DeleteFailed implements Exception {
  const DeleteFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

class Account {
  Account._();

  /// Asks Google to confirm it's still you. Firebase only deletes an account
  /// after a recent sign-in. Returns false if the person backed out.
  static Future<bool> confirmIdentity() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await user.reauthenticateWithProvider(GoogleAuthProvider());
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'web-context-canceled' || e.code == 'canceled') {
        return false;
      }
      if (e.code == 'user-mismatch') {
        throw const DeleteFailed(
          'That was a different Google account. Choose the one you signed in with.',
        );
      }
      throw DeleteFailed(_authMessage(e));
    }
  }

  /// Removes everything: what's on the phone, everything stored in the
  /// account, then the sign-in itself. Call [confirmIdentity] first.
  static Future<void> deleteEverything(Repo repo) async {
    try {
      await repo.deleteAllData().timeout(const Duration(seconds: 60));
    } on FirebaseException catch (e) {
      debugPrint('Delete data failed: $e');
      throw const DeleteFailed(
        'Couldn’t reach TaskPomo’s servers. Check your connection and try again.',
      );
    } catch (e) {
      debugPrint('Delete data failed: $e');
      throw const DeleteFailed(
        'Deleting took too long. Check your connection and try again.',
      );
    }
    // After the data, so the app's own sync (which reacts to the deletes)
    // can't hand the guard its old app list again.
    await _clearPhone();
    try {
      await FirebaseAuth.instance.currentUser?.delete();
    } on FirebaseAuthException catch (e) {
      throw DeleteFailed(_authMessage(e));
    }
  }

  /// Signs out and clears what this account left on the phone, so the guard
  /// doesn't keep pausing apps and the widget doesn't keep showing its day.
  static Future<void> signOut() async {
    await _clearPhone();
    await FirebaseAuth.instance.signOut();
  }

  static Future<void> _clearPhone() async {
    await ScrollGuard.reset();
    await WidgetSync.clear();
    await Notifications.cancelAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static String _authMessage(FirebaseAuthException e) => switch (e.code) {
    'network-request-failed' =>
      'No connection. Check your internet and try again.',
    'requires-recent-login' => 'Please confirm with Google again, then retry.',
    _ => 'Google sign-in didn’t go through (${e.code}). Try again.',
  };
}
