import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App Check proves requests come from the real TaskPomo, so nobody can
/// spend the project's Gemini quota (or read Firestore) with its keys.
///
/// It uses Play Integrity, which only vouches for copies installed from
/// Google Play. On any other copy the token request fails, and the AI
/// library then fails the whole request, so App Check is switched on only
/// for Play installs. Copies installed by hand still work as long as the
/// Firebase console doesn't enforce App Check; once it does, only Play
/// installs can use AI recaps.
class AppCheck {
  AppCheck._();

  static const _ch = MethodChannel('taskpomo/app');
  static const _playStore = 'com.android.vending';

  static Future<void> activate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final installer = await _ch.invokeMethod<String>('installer');
      if (installer != _playStore) return;
      await FirebaseAppCheck.instance.activate(
        providerAndroid: const AndroidPlayIntegrityProvider(),
      );
    } catch (e) {
      debugPrint('App Check not started: $e');
    }
  }
}
