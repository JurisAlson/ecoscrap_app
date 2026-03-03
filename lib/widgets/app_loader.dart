import 'dart:ui';
import 'package:flutter/material.dart';

class AppLoader {
  static bool _isShowing = false;

  static Future<void> show(
    BuildContext context, {
    String title = "Loading…",
    String message = "Please wait a moment.",
    Widget? preview,
  }) async {
    if (_isShowing) return;
    _isShowing = true;

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "AppLoader",
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) {
        return _LoaderOverlay(
          title: title,
          message: message,
          preview: preview,
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );

    // When dialog closes, reset flag
    _isShowing = false;
  }

  static void hide(BuildContext context) {
    if (!_isShowing) return;

    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();

    // showGeneralDialog closes async; prevent double close
    _isShowing = false;
  }
}

class _LoaderOverlay extends StatelessWidget {
  const _LoaderOverlay({
    required this.title,
    required this.message,
    this.preview,
  });

  final String title;
  final String message;
  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF1FA9A7);
    const Color bgColor = Color(0xFF0F172A);

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: 330,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (preview != null) ...[
                    Container(
                      width: double.infinity,
                      height: 140,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.10)),
                        color: Colors.white.withOpacity(0.04),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: preview!,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Logo / icon bubble
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: primaryColor.withOpacity(0.22)),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),

                  const SizedBox(height: 14),

                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      backgroundColor: Colors.white.withOpacity(0.10),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // tiny footer to make it feel polished
                  Text(
                    "EcoScrap • Please don’t close the app",
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}