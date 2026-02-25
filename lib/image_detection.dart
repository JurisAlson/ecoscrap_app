// lib/pages/image_detection_page.dart
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'detection_result_page.dart'; // must contain DetectionResultPage + DetectionStatus enum
import '../services/tflite_service.dart';

class ImageDetectionPage extends StatefulWidget {
  const ImageDetectionPage({super.key});

  @override
  State<ImageDetectionPage> createState() => _ImageDetectionPageState();
}

class _ImageDetectionPageState extends State<ImageDetectionPage> {
  final ImagePicker _picker = ImagePicker();
  File? _image;

  bool _isPickingImage = false;

  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  // ✅ Show instructions BEFORE opening camera
  Future<bool> _showScanInstructions() async {
    bool agreed = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              backgroundColor: bgColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                "Before you scan",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "This scanner detects PLASTICS.",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "It will tell you if the item is recyclable and likely accepted by nearby junkshops.",
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "For best results:",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "• Take a clear photo in good lighting.\n"
                      "• Fill the frame with the item.\n"
                      "• Avoid blur and reflections.\n"
                      "• Show 1 item ONLY.",
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: primaryColor,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Tip: If the result looks wrong, try again with a closer and brighter photo.",
                              style: TextStyle(
                                color: Colors.grey.shade300,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    CheckboxListTile(
                      value: agreed,
                      onChanged: (v) => setLocalState(() => agreed = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      activeColor: primaryColor,
                      checkColor: bgColor,
                      title: const Text(
                        "I understand and want to continue",
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey.shade300),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: bgColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: agreed ? () => Navigator.pop(ctx, true) : null,
                  child: const Text("Continue"),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }

  Future<void> _captureImageWithCamera() async {
    if (_isPickingImage) return;

    final ok = await _showScanInstructions();
    if (!ok) return;

    _isPickingImage = true;

    try {
      final XFile? capturedFile =
          await _picker.pickImage(source: ImageSource.camera);
      if (capturedFile == null) return;

      setState(() {
        _image = File(capturedFile.path);
      });

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final double p = await TFLiteService.runModel(_image!.path);

      // ✅ Conservative YES + Uncertain band (recommended for current model)
      const double yesThreshold = 0.70; // strong YES
      const double noThreshold = 0.35; // strong NO

      DetectionStatus status;
      String itemName;
      double confidence;

      if (p >= yesThreshold) {
        status = DetectionStatus.recyclable;
        itemName = "Recyclable Plastic";
        confidence = p;
      } else if (p <= noThreshold) {
        status = DetectionStatus.nonRecyclable;
        itemName = "Non-Recyclable Item";
        confidence = 1.0 - p;
      } else {
        status = DetectionStatus.uncertain;
        itemName = "Uncertain Result";
        confidence = (p - 0.5).abs() * 2.0; // 0..1 strength
      }

      if (!mounted) return;

      // ✅ close loading dialog safely
      Navigator.of(context, rootNavigator: true).pop();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DetectionResultPage(
            status: status,
            itemName: itemName,
            confidence: confidence,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        // close loader if open
        Navigator.of(context, rootNavigator: true).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      _isPickingImage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          _blurCircle(primaryColor.withOpacity(0.15), 300,
              top: -100, right: -100),
          _blurCircle(Colors.green.withOpacity(0.1), 350,
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
                        "Image Detection",
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 260,
                          height: 260,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: _image != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Image.file(
                                    _image!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.image_outlined,
                                        size: 60, color: Colors.grey),
                                    SizedBox(height: 12),
                                    Text(
                                      "No image captured",
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: 220,
                          height: 54,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: bgColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _captureImageWithCamera,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text(
                              "Open Camera",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_image != null)
                          Text(
                            "Image captured. Ready to analyze...",
                            style: TextStyle(color: Colors.grey.shade400),
                          ),
                      ],
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