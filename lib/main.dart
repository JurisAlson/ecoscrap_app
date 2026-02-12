import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'auth/splash_screen.dart';
import 'auth/login_page.dart';
import 'role_gate.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

 // await FirebaseAppCheck.instance.activate(
 //   androidProvider: AndroidProvider.debug,
 // );

  // ✅ DEBUG: prints auth + claims to terminal
  FirebaseAuth.instance.idTokenChanges().listen((user) async {
    if (user == null) {
      print("AUTH: signed out");
      return;
    }

    final token = await user.getIdTokenResult(true);
    print("AUTH: uid=${user.uid} email=${user.email}");
    print("CLAIMS: ${token.claims}");
    print("IS_ADMIN: ${token.claims?['admin']}");
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EcoScrap App',
      theme: ThemeData(primarySwatch: Colors.teal),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginPage(),
        '/dashboard': (context) => const RoleGate(),
      },
    );
  }
}
