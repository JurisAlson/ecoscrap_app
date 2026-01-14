import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'detection_result_page.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class ImageDetectionPage extends StatefulWidget {
  const ImageDetectionPage({super.key});

  @override
  State<ImageDetectionPage> createState() => _ImageDetectionPageState();
}

class _ImageDetectionPageState extends State<ImageDetectionPage> {
  final ImagePicker _picker = ImagePicker();
  File? _image;

  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  // ================= CAMERA =================
  Future<void> _captureImageWithCamera() async {
    final XFile? capturedFile =
        await _picker.pickImage(source: ImageSource.camera);

    if (capturedFile != null) {
      setState(() {
        _image = File(capturedFile.path);
      });

      // 🔹 TEMP: Simulate AI detection result
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DetectionResultPage(
              isRecyclable: true, // TensorFlow output later
              itemName: "Plastic Bottle",
              confidence: 0.92,
            ),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // ===== BACKGROUND BLUR =====
          _blurCircle(primaryColor.withOpacity(0.15), 300,
              top: -100, right: -100),
          _blurCircle(Colors.green.withOpacity(0.1), 350,
              bottom: 100, left: -100),

          SafeArea(
            child: Column(
              children: [
                // ===== TOP BAR =====
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Image Detection",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),

                // ===== CONTENT =====
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // IMAGE PREVIEW
                        Container(
                          width: 260,
                          height: 260,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.1)),
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

                        // OPEN CAMERA BUTTON
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
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        if (_image != null)
                          Text(
                            "Analyzing image...",
                            style:
                                TextStyle(color: Colors.grey.shade400),
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

  // ================= BLUR HELPER =================
  Widget _blurCircle(Color color, double size,
      {double? top, double? bottom, double? left, double? right}) {
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
