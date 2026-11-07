import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/password_screen.dart';
import 'screens/register_screen.dart';
import 'store.dart';
import 'theme.dart';

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

class EstateApp extends StatelessWidget {
  const EstateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nilaya Living',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final user = store.currentUser;
          if (user == null) return const LoginScreen();
          // Registrasi mandiri: tunggu verifikasi pengelola.
          if (user.role == Role.pendaftar) {
            return const PendingRegistrationScreen();
          }
          // Login pertama dengan password sementara dari pengelola.
          if (user.mustChangePassword) {
            return const ChangePasswordScreen(forced: true);
          }
          return const HomeShell();
        },
      ),
    );
  }
}
