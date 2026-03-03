// lib/pages/image_detection_page.dart
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'detection_result_page.dart'; // must contain DetectionResultPage + DetectionStatus enum
import '../services/tflite_service.dart';
import '../widgets/app_loader.dart';

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

  // ✅ ORIGINAL GUIDE (Good lighting / Fill frame / Plastic only / Avoid blur)
  // ✅ ✔ badge TOP for good, ✖ badge BOTTOM for bad
  Future<bool> _showScanInstructions() async {
    bool agreed = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            int pageIndex = 0;
            final PageController controller = PageController();

            final pages = [
  {
    "title": "1) Good lighting",
    "subtitle": "Scan in a bright area. Avoid dark or yellow lighting.",
    "items": [
      // ✅ TOP = VALID (check)
      {"asset": "assets/plastic_validation/valid_1/plastic49.jpg", "good": true},
      {"asset": "assets/plastic_validation/valid_1/plastic419.jpg", "good": true},

      // ❌ BOTTOM = INVALID (x)
      {"asset": "assets/plastic_validation/invalid_1/plastic156.jpg", "good": false},
      {"asset": "assets/plastic_validation/invalid_1/plastic159.jpg", "good": false},
    ],
  },
  {
    "title": "2) Fill the frame",
    "subtitle": "Move closer so the item fills most of the photo.",
    "items": [
      {"asset": "assets/plastic_validation/valid_2/plastic155.jpg", "good": true},
      {"asset": "assets/plastic_validation/valid_2/plastic160.jpg", "good": true},
      {"asset": "assets/plastic_validation/invalid_2/plastic43.jpg", "good": false},
      {"asset": "assets/plastic_validation/invalid_2/plastic170.jpg", "good": false},
    ],
  },
  {
    "title": "3) PLASTIC items only",
    "subtitle": "Avoid taking scanning non plastic materials such as Glass, Metal ETC.",
    "items": [
      {"asset": "assets/plastic_validation/valid_3/plastic291.jpg", "good": true},
      {"asset": "assets/plastic_validation/valid_3/plastic317.jpg", "good": true},
      {"asset": "assets/plastic_validation/invalid_3/trash12.jpg", "good": false},
      {"asset": "assets/plastic_validation/invalid_3/trash67.jpg", "good": false},
    ],
  },
  {
    "title": "4) Avoid glare & blur",
    "subtitle": "Keep steady and reduce reflections on shiny plastics.",
    "items": [
      {"asset": "assets/plastic_validation/valid_4/plastic47.jpg", "good": true},
      {"asset": "assets/plastic_validation/valid_4/plastic468.jpg", "good": true},
      {"asset": "assets/plastic_validation/invalid_4/invalid2.jpg", "good": false},
      {"asset": "assets/plastic_validation/invalid_4/invalid4_1.jpg", "good": false},
    ],
  },
];

            Widget swipeHint() {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left, size: 18, color: Colors.white.withOpacity(0.65)),
                    const SizedBox(width: 2),
                    Icon(Icons.swipe, size: 18, color: Colors.white.withOpacity(0.85)),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 18, color: Colors.white.withOpacity(0.65)),
                  ],
                ),
              );
            }

            Widget safeAssetImage(String path) {
  return Image.asset(
    path,
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          "Missing:\n$path",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 10,
            height: 1.2,
          ),
        ),
      ),
    ),
  );
}
            Widget tile(Map<String, dynamic> item) {
  final bool good = item["good"] as bool;

  final Color badgeColor = good ? Colors.green : Colors.red;
  final IconData badgeIcon = good ? Icons.check : Icons.close;

  return Container(
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.08)),
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: safeAssetImage(item["asset"] as String),
          ),
        ),

        // ✅ CHECK stays TOP, ❌ X stays BOTTOM (proper comparison)
        Positioned(
          top: good ? 8 : null,
          bottom: good ? null : 8,
          right: 8,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.90),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(badgeIcon, size: 14, color: Colors.white),
          ),
        ),
      ],
    ),
  );
}
            Widget dots() {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  pages.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 6,
                    width: pageIndex == i ? 18 : 6,
                    decoration: BoxDecoration(
                      color: pageIndex == i ? primaryColor : Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              backgroundColor: bgColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  Icon(Icons.camera_alt, color: primaryColor),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Before you scan",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  swipeHint(),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Swipe through the guides. Try to match the GOOD examples.",
                      style: TextStyle(color: Colors.grey.shade300, fontSize: 13, height: 1.3),
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      height: 290,
                      child: PageView.builder(
                        controller: controller,
                        itemCount: pages.length,
                        onPageChanged: (i) => setLocalState(() => pageIndex = i),
                        itemBuilder: (_, p) {
                          final page = pages[p];
                          final items = (page["items"] as List).cast<Map<String, dynamic>>();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                page["title"] as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                page["subtitle"] as String,
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 12, height: 1.25),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: items.length,
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 10,
                                    childAspectRatio: 1,
                                  ),
                                  itemBuilder: (_, i) => tile(items[i]),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 10),
                    dots(),

                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: primaryColor, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Best accuracy: 1 plastic item only, bright light, close-up, steady hands.",
                              style: TextStyle(color: Colors.grey.shade300, fontSize: 12, height: 1.3),
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
                  child: Text("Cancel", style: TextStyle(color: Colors.grey.shade300)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: bgColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      final XFile? capturedFile = await _picker.pickImage(source: ImageSource.camera);
      if (capturedFile == null) return;

      setState(() {
        _image = File(capturedFile.path);
      });

      if (!mounted) return;

      AppLoader.show(
        context,
        title: "Scanning your photo…",
        message: "Analyzing plastic type. This will only take a moment.",
        preview: Image.file(_image!, fit: BoxFit.cover),
      );

      await Future.delayed(Duration.zero);
      await WidgetsBinding.instance.endOfFrame;

      final double p = await TFLiteService.runModel(_image!.path);

      const double yesThreshold = 0.80;
      const double noThreshold = 0.35;

      late DetectionStatus status;
      late String itemName;
      late double confidence;

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
        confidence = (p - 0.5).abs() * 2.0;
      }

      if (!mounted) return;

      AppLoader.hide(context);

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
      if (!mounted) return;
      AppLoader.hide(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
          _blurCircle(primaryColor.withOpacity(0.15), 300, top: -100, right: -100),
          _blurCircle(Colors.green.withOpacity(0.1), 350, bottom: 100, left: -100),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: _image != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Image.file(_image!, fit: BoxFit.cover),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.image_outlined, size: 60, color: Colors.grey),
                                    SizedBox(height: 12),
                                    Text("No image captured", style: TextStyle(color: Colors.grey)),
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
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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