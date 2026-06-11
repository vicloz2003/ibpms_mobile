import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/offline/connectivity_service.dart';
import 'core/offline/sync_queue.dart';
import 'core/services/fcm_service.dart';
import 'core/storage/secure_storage.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/processes/screens/process_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase init (RF-28) — graceful degradation if not configured
  try {
    await Firebase.initializeApp();
    // Must be registered before runApp and use a top-level handler (RF-29/30).
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    await FcmService.init();
  } catch (_) {
    // Firebase not configured or google-services.json missing — skip silently
  }

  bool isLoggedIn;
  try {
    isLoggedIn = await SecureStorageService.isLoggedIn();
  } catch (_) {
    await SecureStorageService.clearAll();
    isLoggedIn = false;
  }

  // Boot the offline layer (RNF-6)
  ConnectivityService.instance;
  if (isLoggedIn) {
    unawaited(SyncQueue.instance.flush());
    // Register FCM token with backend when already logged in
    unawaited(FcmService.registerToken());
  }

  runApp(
    ProviderScope(
      child: IBPMSApp(isLoggedIn: isLoggedIn),
    ),
  );
}

class IBPMSApp extends StatelessWidget {
  final bool isLoggedIn;
  const IBPMSApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iBPMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1976D2),
        ),
        useMaterial3: true,
      ),
      home: isLoggedIn
          ? const ProcessListScreen()
          : const LoginScreen(),
    );
  }
}
