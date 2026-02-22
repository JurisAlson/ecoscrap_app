import 'dart:ui';
import 'package:flutter/material.dart';

class AdminTheme {
  static const primary = Color(0xFF1FA9A7);
  static const bg = Color(0xFF0F172A);

  static Widget background({required Widget child}) {
    return Stack(
      children: [
        Positioned(
          top: -100,
          right: -100,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withOpacity(0.15),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
        SafeArea(child: child),
      ],
    );
  }
}