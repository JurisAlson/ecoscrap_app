// lib/services/tflite_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class TFLiteService {
  static const String _modelAssetPath = 'assets/models/plastic_model.tflite';
  static const int _inputSize = 224;
  static const bool _debug = false;

  static Interpreter? _interpreter;
  static bool _isRunning = false;

  static Future<void> init() async {
    if (_interpreter != null) return;

    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(_modelAssetPath, options: options);

    if (_debug) {
      final in0 = _interpreter!.getInputTensor(0);
      final out0 = _interpreter!.getOutputTensor(0);
      debugPrint('TFLite input shape: ${in0.shape}, type: ${in0.type}');
      debugPrint('TFLite output shape: ${out0.shape}, type: ${out0.type}');
    }
  }

  static Future<double> runModel(String imagePath) async {
    if (_isRunning) {
      throw Exception('Model is already running.');
    }

    _isRunning = true;

    try {
      await init();
      final interpreter = _interpreter!;

      final List<List<List<List<double>>>> input =
          await compute(_preprocessSingleInput, imagePath);

      final output = List.generate(1, (_) => List.filled(1, 0.0));

      interpreter.run(input, output);

      final p = (output[0][0] as num).toDouble().clamp(0.0, 1.0);

      if (_debug) {
        debugPrint('TFLite prediction: $p');
      }

      return p;
    } finally {
      _isRunning = false;
    }
  }

  static void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}

Future<List<List<List<List<double>>>>> _preprocessSingleInput(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('Could not decode image.');
  }

  final cropped = _centerSquareCrop(decoded);
  final tensor = _toInputTensorNoBatch(cropped);

  return [tensor]; // [1,224,224,3]
}

img.Image _centerSquareCrop(img.Image image) {
  final int s = image.width < image.height ? image.width : image.height;
  final int x = (image.width - s) ~/ 2;
  final int y = (image.height - s) ~/ 2;

  return img.copyCrop(image, x: x, y: y, width: s, height: s);
}

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