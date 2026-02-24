// lib/services/tflite_service.dart
import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// Service that caches interpreter and runs multi-crop (majority) inference.
class TFLiteService {
  static Interpreter? _interpreter;

  static Future<void> init() async {
    if (_interpreter != null) return;

    _interpreter = await Interpreter.fromAsset(
      'assets/models/plastic_model.tflite',
      options: InterpreterOptions()..threads = 2,
    );

    // Optional debug prints
    final in0 = _interpreter!.getInputTensor(0);
    final out0 = _interpreter!.getOutputTensor(0);
    // ignore: avoid_print
    print('Input shape: ${in0.shape}, type: ${in0.type}');
    // ignore: avoid_print
    print('Output shape: ${out0.shape}, type: ${out0.type}');
  }

  /// Returns average score across 5 crops:
  /// top-left, top-right, bottom-left, bottom-right, center
  static Future<double> runModel(String imagePath) async {
    await init();
    final interpreter = _interpreter!;

    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception("Could not decode image.");
    }

    final crops = _fiveCrops(decoded);

    double sum = 0.0;
    for (final crop in crops) {
      final input = _toInputTensor(crop, 224);
      final output = List.generate(1, (_) => List.filled(1, 0.0)); // [1,1]
      interpreter.run(input, output);
      sum += output[0][0];
    }

    return sum / crops.length;
  }

  // ---------------- helpers ----------------

  static List<img.Image> _fiveCrops(img.Image image) {
    final s = image.width < image.height ? image.width : image.height;

    int clamp(int v, int min, int max) => v < min ? min : (v > max ? max : v);

    final right = image.width - s;
    final bottom = image.height - s;
    final centerX = (image.width - s) ~/ 2;
    final centerY = (image.height - s) ~/ 2;

    final points = <List<int>>[
      [0, 0], // top-left
      [right, 0], // top-right
      [0, bottom], // bottom-left
      [right, bottom], // bottom-right
      [centerX, centerY], // center
    ];

    return points.map((xy) {
      final x = clamp(xy[0], 0, image.width - s);
      final y = clamp(xy[1], 0, image.height - s);
      return img.copyCrop(image, x: x, y: y, width: s, height: s);
    }).toList();
  }

  static List _toInputTensor(img.Image image, int inputSize) {
    final resized = img.copyResize(image, width: inputSize, height: inputSize);

    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (_) => List.generate(
          inputSize,
          (_) => List.filled(3, 0.0),
        ),
      ),
    );

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final p = resized.getPixel(x, y);
        input[0][y][x][0] = p.r / 255.0;
        input[0][y][x][1] = p.g / 255.0;
        input[0][y][x][2] = p.b / 255.0;
      }
    }
    return input;
  }
}