import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/storage/secure_storage.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/processes/screens/process_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool isLoggedIn;
  try {
    isLoggedIn = await SecureStorageService.isLoggedIn();
  } catch (_) {
    // Fallback: Web Crypto OperationError on first Chrome run.
    // Clearing storage and starting unauthenticated is safe.
    await SecureStorageService.clearAll();
    isLoggedIn = false;
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
