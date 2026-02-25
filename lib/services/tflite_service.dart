// lib/services/tflite_service.dart
import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// Deployment-ready TFLite service for binary (sigmoid) plastic classifier.
/// - Input:  [1, 224, 224, 3] float32 (NHWC)
/// - Output: [1, 1] float32 (sigmoid probability of "recyclable")
///
/// Uses 5-crop + conservative MIN aggregation to reduce false "recyclable".
class TFLiteService {
  static const String _modelAssetPath = 'assets/models/plastic_model.tflite';
  static const int _inputSize = 224;

  // Toggle for logs during development; keep false for release.
  static const bool _debug = false;

  static Interpreter? _interpreter;

  static Future<void> init() async {
    if (_interpreter != null) return;

    _interpreter = await Interpreter.fromAsset(
      _modelAssetPath,
      options: InterpreterOptions()..threads = 2,
    );

    if (_debug) {
      final in0 = _interpreter!.getInputTensor(0);
      final out0 = _interpreter!.getOutputTensor(0);
      // ignore: avoid_print
      print('###TFLITE### Input shape: ${in0.shape}, type: ${in0.type}');
      // ignore: avoid_print
      print('###TFLITE### Output shape: ${out0.shape}, type: ${out0.type}');
    }
  }

  /// Returns a single probability p in [0,1]:
  /// p = P(recyclable)
  ///
  /// Conservative aggregation:
  /// - MIN across 5 crops (reject if any crop looks non-recyclable)
  static Future<double> runModel(String imagePath) async {
    await init();
    final interpreter = _interpreter!;

    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Could not decode image.');
    }

    final crops = _fiveCrops(decoded);

    double minP = 1.0;
    for (final crop in crops) {
      final input = _toInputTensor(crop);
      final output = List.generate(1, (_) => List.filled(1, 0.0)); // [1,1]

      interpreter.run(input, output);

      final p = output[0][0].toDouble();
      if (p < minP) minP = p;

      if (_debug) {
        // ignore: avoid_print
        print('###TFLITE### crop p=$p');
      }
    }

    if (_debug) {
      // ignore: avoid_print
      print('###TFLITE### final(min) p=$minP');
    }

    // Clamp for safety
    if (minP < 0.0) return 0.0;
    if (minP > 1.0) return 1.0;
    return minP;
  }

  // ---------------- helpers ----------------

  /// 5-crop from the largest centered square:
  /// top-left, top-right, bottom-left, bottom-right, center
  static List<img.Image> _fiveCrops(img.Image image) {
    final s = image.width < image.height ? image.width : image.height;

    int clamp(int v, int min, int max) => v < min ? min : (v > max ? max : v);

    final right = image.width - s;
    final bottom = image.height - s;
    final centerX = (image.width - s) ~/ 2;
    final centerY = (image.height - s) ~/ 2;

    final points = <List<int>>[
      [0, 0],
      [right, 0],
      [0, bottom],
      [right, bottom],
      [centerX, centerY],
    ];

    return points.map((xy) {
      final x = clamp(xy[0], 0, image.width - s);
      final y = clamp(xy[1], 0, image.height - s);
      return img.copyCrop(image, x: x, y: y, width: s, height: s);
    }).toList();
  }

  /// Converts image -> [1,224,224,3] float32 normalized to [-1,1]
  /// (MobileNetV2-style)
  static List _toInputTensor(img.Image image) {
    final resized = img.copyResize(image, width: _inputSize, height: _inputSize);

    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (_) => List.generate(
          _inputSize,
          (_) => List.filled(3, 0.0),
        ),
      ),
    );

    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final p = resized.getPixel(x, y);

        // [-1,1] normalization
        input[0][y][x][0] = (p.r / 127.5) - 1.0;
        input[0][y][x][1] = (p.g / 127.5) - 1.0;
        input[0][y][x][2] = (p.b / 127.5) - 1.0;
      }
    }

    return input;
  }

  /// Optional: call if you want to free resources on app exit.
  static void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}