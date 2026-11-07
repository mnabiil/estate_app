import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    await store.enableFirebase();
  } catch (e) {
    debugPrint('Firebase tidak aktif, berjalan dalam mode demo. ($e)');
  }
  runApp(const EstateApp());
}

const _seedColor = Color(0xFF2E7D5B);

class EstateApp extends StatelessWidget {
  const EstateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Griya Kita',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seedColor, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: _seedColor,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: store,
        builder: (context, _) =>
            store.currentUser == null ? const LoginScreen() : const HomeShell(),
      ),
    );
  }
}
