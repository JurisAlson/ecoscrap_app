// lib/services/tflite_service.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class TFLiteService {
  static const String _modelAssetPath = 'assets/models/plastic_model.tflite';
  static const int _inputSize = 224;

  static Interpreter? _interpreter;
  static bool _isRunning = false;

  static Future<void> init() async {
    if (_interpreter != null) return;

    try {
      final options = InterpreterOptions()..threads = 1;

      _interpreter = await Interpreter.fromAsset(
        _modelAssetPath,
        options: options,
      );

      final in0 = _interpreter!.getInputTensor(0);
      final out0 = _interpreter!.getOutputTensor(0);

      debugPrint('TFLite init success');
      debugPrint('TFLite input shape: ${in0.shape}, type: ${in0.type}');
      debugPrint('TFLite output shape: ${out0.shape}, type: ${out0.type}');
    } catch (e, st) {
      debugPrint('TFLite init failed: $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  static Future<double> runModel(String imagePath) async {
    if (_isRunning) {
      throw Exception('Model is already running.');
    }

    _isRunning = true;

    try {
      debugPrint('TFLite: init start');
      await init();
      debugPrint('TFLite: init done');

      final interpreter = _interpreter!;

      debugPrint('TFLite: preprocess start');
      final Float32List input = await compute(_preprocessSingleInput, imagePath);
      debugPrint('TFLite: preprocess done');

      final output = List.generate(1, (_) => List.filled(1, 0.0));

      debugPrint('TFLite: inference start');
      interpreter.run(input.reshape([1, _inputSize, _inputSize, 3]), output);
      debugPrint('TFLite: inference done');

      final double p = (output[0][0] as num).toDouble().clamp(0.0, 1.0);
      debugPrint('TFLite prediction: $p');

      return p;
    } catch (e, st) {
      debugPrint('TFLite runModel failed: $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    } finally {
      _isRunning = false;
    }
  }

  static void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}

Future<Float32List> _preprocessSingleInput(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('Could not decode image.');
  }

  final cropped = _centerSquareCrop(decoded);
  return _toInputBuffer(cropped);
}

img.Image _centerSquareCrop(img.Image image) {
  final int s = image.width < image.height ? image.width : image.height;
  final int x = (image.width - s) ~/ 2;
  final int y = (image.height - s) ~/ 2;

  return img.copyCrop(
    image,
    x: x,
    y: y,
    width: s,
    height: s,
  );
}

Float32List _toInputBuffer(img.Image image) {
  final resized = img.copyResize(
    image,
    width: TFLiteService._inputSize,
    height: TFLiteService._inputSize,
  );

  final buffer =
      Float32List(TFLiteService._inputSize * TFLiteService._inputSize * 3);

  int index = 0;

  for (int y = 0; y < TFLiteService._inputSize; y++) {
    for (int x = 0; x < TFLiteService._inputSize; x++) {
      final pixel = resized.getPixel(x, y);

      buffer[index++] = (pixel.r / 127.5) - 1.0;
      buffer[index++] = (pixel.g / 127.5) - 1.0;
      buffer[index++] = (pixel.b / 127.5) - 1.0;
    }
  }

  return buffer;
}