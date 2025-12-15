import 'package:flutter/material.dart';
import 'splash_screen.dart';

void main() {
  runApp(const EcoScrapApp());
}

class EcoScrapApp extends StatelessWidget {
  const EcoScrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}
