import 'package:flutter/material.dart';
import 'login_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Fade animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(_controller);

    // Start fade animation
    _controller.forward();

    // After fade → slide transition to login page
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        _createRoute(), // custom slide animation route
      );
    });
  }

  // Custom slide-up transition
  Route _createRoute() {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 700),
      pageBuilder: (context, animation, secondaryAnimation) => const LoginPage(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0); // start from bottom
        const end = Offset.zero;        // end at the center
        final tween = Tween(begin: begin, end: end)
            .chain(CurveTween(curve: Curves.easeOutCubic));

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Image.asset(
            "assets/images/ecoscrap_logo.png",
            width: 200,
          ),
        ),
      ),
    );
  }
}
