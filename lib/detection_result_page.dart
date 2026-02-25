// lib/pages/detection_result_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';

import 'geomapping.dart';

enum DetectionStatus { recyclable, nonRecyclable, uncertain }

class DetectionResultPage extends StatelessWidget {
  final DetectionStatus status;
  final String itemName;
  final double confidence; // 0..1

  const DetectionResultPage({
    super.key,
    required this.status,
    required this.itemName,
    required this.confidence,
  });

  bool get isRecyclable => status == DetectionStatus.recyclable;
  bool get isUncertain => status == DetectionStatus.uncertain;

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = const Color(0xFF1FA9A7);
    final Color bgColor = const Color(0xFF0F172A);

    final Color statusColor = isUncertain
        ? Colors.amber
        : (isRecyclable ? Colors.green : Colors.red);

    final IconData statusIcon = isUncertain
        ? Icons.help_outline
        : (isRecyclable ? Icons.check_circle : Icons.cancel);

    final String subtitleText = isUncertain
        ? "We’re not sure about this photo.\nTry again with better lighting and closer framing."
        : (isRecyclable
            ? "This item is recyclable."
            : "This item is not recyclable.\nPlease dispose of it responsibly.");

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          _blurCircle(primaryColor.withOpacity(0.15), 300,
              top: -100, right: -100),
          _blurCircle(statusColor.withOpacity(0.10), 350,
              bottom: 100, left: -100),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Detection Result",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(statusIcon, color: statusColor, size: 100),
                          const SizedBox(height: 24),
                          Text(
                            itemName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Confidence: ${(confidence * 100).toStringAsFixed(1)}%",
                            style: TextStyle(color: Colors.grey.shade400),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            subtitleText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 26),

                          // ✅ Only show junkshop button when recyclable
                          if (isRecyclable) ...[
                            _actionButton(
                              icon: Icons.location_on,
                              label: "Find Nearest Junkshop",
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const GeoMappingPage(),
                                  ),
                                );
                              },
                              outlined: true,
                              color: primaryColor,
                              textColor: primaryColor,
                            ),
                            const SizedBox(height: 12),
                          ],

                          // ✅ Always allow Scan Again
                          _actionButton(
                            icon: Icons.camera_alt,
                            label: "Scan Again",
                            onTap: () => Navigator.pop(context),
                            outlined: true,
                            color: Colors.white.withOpacity(0.85),
                            textColor: Colors.white,
                          ),

                          const SizedBox(height: 18),
                          TextButton(
                            onPressed: () =>
                                Navigator.popUntil(context, (r) => r.isFirst),
                            child: const Text(
                              "Back to Dashboard",
                              style: TextStyle(
                                color: Color(0xFF1FA9A7),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool outlined = false,
    required Color color,
    required Color textColor,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, color: color),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(label),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: textColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
    );
  }

  Widget _blurCircle(
    Color color,
    double size, {
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}