import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/app_check.dart';
import 'services/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? setupError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    await AppCheck.activate();
  } catch (e) {
    setupError = e;
  }
  final prefs = await SharedPreferences.getInstance();
  await Notifications.init();
  runApp(TaskPomoApp(prefs: prefs, setupError: setupError));
}
