import 'dart:io';
import 'package:flutter/foundation.dart'; // compute()
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Deployment-ready TFLite service for binary (sigmoid) plastic classifier.
/// - Input:  [1, 224, 224, 3] float32 (NHWC)
/// - Output: [1, 1] float32 (sigmoid probability of "recyclable")
///
/// Uses 5-crop + conservative MIN aggregation to reduce false "recyclable".
class TFLiteService {
  static const String _modelAssetPath = 'assets/models/plastic_model.tflite';
  static const int _inputSize = 224;

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

  /// Returns p in [0,1] where p = P(recyclable).
  /// Conservative aggregation: MIN across 5 crops.
  static Future<double> runModel(String imagePath) async {
    await init();
    final interpreter = _interpreter!;

    // ✅ Heavy preprocessing in background isolate:
    // decode + crops + resize + tensor build
    final List<List<List<List<double>>>> inputs =
        await compute(_preprocessFiveInputs, imagePath);

    double minP = 1.0;

    for (final input4d in inputs) {
      // Wrap into [1,224,224,3]
      final input = [input4d];

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

    return minP.clamp(0.0, 1.0);
  }

  static void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}

/// ---------------------------
/// ISOLATE PREPROCESSING
/// ---------------------------
/// Must be a TOP-LEVEL function for compute().
Future<List<List<List<List<double>>>>> _preprocessFiveInputs(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('Could not decode image.');
  }

  final crops = _fiveCrops(decoded);

  // Convert each crop into [224][224][3] (we add batch later)
  final inputs = <List<List<List<double>>>>[];
  for (final crop in crops) {
    inputs.add(_toInputTensorNoBatch(crop));
  }
  return inputs;
}

/// 5-crop from largest centered square:
/// top-left, top-right, bottom-left, bottom-right, center
List<img.Image> _fiveCrops(img.Image image) {
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

/// Converts image -> [224][224][3] float32 normalized to [-1,1] (MobileNetV2-style)
List<List<List<double>>> _toInputTensorNoBatch(img.Image image) {
  const int inputSize = 224;
  final resized = img.copyResize(image, width: inputSize, height: inputSize);

  final out = List.generate(
    inputSize,
    (_) => List.generate(
      inputSize,
      (_) => List.filled(3, 0.0),
    ),
  );

  for (int y = 0; y < inputSize; y++) {
    for (int x = 0; x < inputSize; x++) {
      final p = resized.getPixel(x, y);

      out[y][x][0] = (p.r / 127.5) - 1.0;
      out[y][x][1] = (p.g / 127.5) - 1.0;
      out[y][x][2] = (p.b / 127.5) - 1.0;
    }
  }

  return out;
}